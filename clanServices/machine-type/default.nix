{
  _class = "clan.service";
  manifest = {
    name = "@andrewthomaslee/machine-type";
    description = "Machine profiles for the home fleet: the shared base every machine gets, plus a desktop (pc) or headless (server) role";
    readme = ''
      Every machine in any role gets the shared base (perMachine): the
      external-systems/modules NixOS modules, the org nixpkgs + overlay,
      the networking shim, clan defaults, openssh, motd, locale and the
      base toolset.

      - `pc`: KDE/Wayland desktop with sound, bluetooth and the desktop
        apps.
      - `server`: headless; nix daemon defaults, no desktop.
    '';
    categories = ["System"];
  };

  roles = {
    pc = {
      description = "Personal computer: KDE/Wayland desktop";
      perInstance.nixosModule = ./pc.nix;
    };
    server = {
      description = "Headless server";
      perInstance.nixosModule = ./server.nix;
    };
  };

  # Common configuration for all machine types.
  perMachine.nixosModule = {
    self,
    inputs,
    lib,
    pkgs,
    ...
  }: {
    imports = [
      inputs.modules.nixosModules.default
      self.nixosModules.nixpkgs
      self.nixosModules.networking-shim
    ];

    config = {
      # --- hostSpec options --- #
      hostSpec = {
        clan.enable = true;
        services = {
          motd.enable = true;
          openssh.enable = true;
        };
      };

      # --- nixos options --- #

      # Home-manager: users evaluate their own nixpkgs (no useGlobalPkgs),
      # so the org overlay is applied there too.
      home-manager = {
        useUserPackages = true;
        backupFileExtension = "hm-backup";
        sharedModules = [
          inputs.modules.inputs.plasma-manager.homeModules.plasma-manager
          {nixpkgs.overlays = [inputs.org-pkgs.overlays.default];}
        ];
      };

      # localization
      i18n.defaultLocale = "en_US.UTF-8";
      time.timeZone = "America/Chicago";

      # Services
      services.journald.settings.Journal.SystemMaxUse = "1G";

      # Hardware
      hardware = {
        enableRedistributableFirmware = true;
        graphics.enable = lib.mkDefault true;
      };

      # networking
      networking.nameservers = lib.mkForce [
        "2606:4700:4700::1111"
        "1.1.1.1"
      ];

      # System Packages
      environment = {
        enableAllTerminfo = true;
        localBinInPath = true;
        systemPackages = with pkgs; [
          zstd
          gzip
          rsync
          httpie
          fastfetch
          jq
          yq
        ];
      };
    };
  };
}
