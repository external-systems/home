{
  inputs,
  self,
  lib,
  ...
}: let
  # Custom lib: nixpkgs lib extended with the repo's own helpers
  # (lib/default.nix) at the TOP LEVEL — `customLib.relativeToRoot`, no
  # `.custom` hop. Also exported as `flake.lib` (inputs.<name>.lib for
  # other flakes; `mkLib` is the exportable root-binding factory there,
  # since this repo's `relativeToRoot` is bound to THIS repo's root).
  customLib = lib.extend (_self: _super: import ../lib {inherit lib;});
  inherit (customLib) relativeToRoot;
in {
  # Clan service registration: clanServices/*/flake-module.nix register
  # clan.modules.<name> (upstream clan-core layout; the clanServices/
  # flake-module.nix auto-importer picks up every service directory, so
  # there is no hand-maintained module list). Imported at the TOP LEVEL
  # of the flake-parts module — inside `clan = { ... }` the import would
  # resolve as flake.clan.clan.modules and fail the strict eval.
  imports = [(relativeToRoot "clanServices/flake-module.nix")];

  # ------ Per-System ------ #
  perSystem = {
    pkgs,
    system,
    ...
  }: {
    _module.args = {
      inherit customLib;
      # Make pkgs available in perSystem evaluation as well
      pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [self.overlays.default];
        config.allowUnfree = true;
      };
    };

    # Formatter
    formatter = pkgs.unstable.alejandra;
    # Mkdocs
    documentation.mkdocs-root = relativeToRoot "documentation";
  };

  flake = {
    # Exportable lib for other flakes: inputs.home.lib.mkLib <root>
    lib = import ../lib {inherit lib;};

    # Exportable flake-parts modules for other flakes (plain flakes and
    # devenv projects pulling this repo as an input). The module is
    # exported with home's mkCodeSandbox already bound, so consumers
    # never reference inputs.home inside their config.
    flakeModules.code-sandbox = import ../flakeModules/code-sandbox.nix {
      inherit (customLib) mkCodeSandbox;
    };

    # ------ NixOS Modules ------ #
    nixosModules.default = {...}: {
      # args passed to all modules
      _module.args = {inherit customLib;};

      # customLib (and thus relativeToRoot) for home-manager modules — set
      # here, not per clan service, so non-clan consumers (KubeVirt VM
      # packages, test VMs) get it too.
      home-manager.extraSpecialArgs = {inherit customLib;};

      # pkgs
      nixpkgs = {
        overlays = [self.overlays.default];
        config.allowUnfree = lib.mkDefault true;
        hostPlatform = lib.mkDefault "x86_64-linux";
      };

      # nixosModules imported
      imports =
        [
          inputs.home-manager.nixosModules.home-manager
        ]
        # Import all NixOS Modules from `flake-parts/nixosModules`
        # Filter out profile modules and clan modules
        ++ (lib.attrValues (lib.filterAttrs (
            n: _:
              n
              != "default"
              && !(lib.hasPrefix "profile-" n)
              && !(lib.hasPrefix "clan-" n)
          )
          self.nixosModules));

      # Boot
      boot = {
        tmp = {
          useTmpfs = lib.mkDefault false;
          cleanOnBoot = lib.mkDefault true;
        };
        loader.grub = {
          enable = lib.mkDefault true;
          efiSupport = lib.mkDefault true;
          efiInstallAsRemovable = lib.mkDefault true;
        };
      };
    };

    # ------ Home-manager Default Module ------ #
    homeModules = {
      # Default Home-manager Module for all users
      default = {
        nixpkgs = {
          config.allowUnfree = lib.mkDefault true;
          overlays = [
            self.overlays.default
          ];
        };
        home = {
          stateVersion = "26.11";
          keyboard.layout = "us";
        };
        programs.home-manager.enable = true;

        # Import all Home-manager Modules from `flake-parts/homeModules`
        # Filter out profile modules
        imports = lib.attrValues (lib.filterAttrs (
            n: _:
              n
              != "default"
              && !(lib.hasPrefix "profile-" n)
          )
          self.homeModules);
      };
    };

    # ------ Overlays ------ #
    overlays.default = import (relativeToRoot "overlays") {inherit inputs self;};

    # ------ Templates ------ #
    # Scaffold a new repo from this one: `nix flake init -t .#self`
    templates.self = {
      path = relativeToRoot ".";
      description = "This Flake";
    };

    # --- Clan Configuration ------ #
    clan = {
      inventory = import (relativeToRoot "inventory.nix") {inherit customLib;};
      specialArgs = {inherit customLib inputs self;};
      inherit ((import "${inputs.clan-community}/services/rancher/flake-module.nix" {}).clan) exportInterfaces;
    };
  };
}
