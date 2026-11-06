{
  description = "external-systems home fleet — clan machines consuming the org's pkgs, modules and secrets flakes";

  inputs = {
    # Shared-input authority for the org: nixpkgs, flake-parts and
    # import-tree come from the artifact flake, so there is exactly one
    # nixpkgs. Named org-pkgs, never pkgs: `pkgs` is the nixpkgs package
    # set everywhere else.
    org-pkgs.url = "github:external-systems/pkgs";
    nixpkgs.follows = "org-pkgs/nixpkgs";
    flake-parts.follows = "org-pkgs/flake-parts";
    import-tree.follows = "org-pkgs/import-tree";

    # Consumer-facing inputs only; dev-only inputs go in dev/flake.nix.

    # Clan: inventory, vars, deployment. Rides the one nixpkgs.
    clan-core = {
      url = "https://git.clan.lol/clan/clan-core/archive/main.tar.gz";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };

    # NixOS and home-manager modules (hostSpec.* / homeSpec.*). Brings
    # home-manager, plasma-manager, jovian and external-systems/skills.
    modules = {
      url = "github:external-systems/modules";
      inputs.org-pkgs.follows = "org-pkgs";
    };

    # Fleet values (addresses, interfaces, deploy targets): the private
    # external-systems/secrets, pinned directly because clan can't pass
    # --override-input. Evaluating the machines needs a GitHub token with
    # read access (the devenv shell sets NIX_CONFIG access-tokens from
    # .env). The lock records only its name and revision, not the values.
    secrets = {
      url = "github:external-systems/secrets";
      inputs = {
        org-pkgs.follows = "org-pkgs";
        not-secrets.inputs.org-pkgs.follows = "org-pkgs";
      };
    };

    # Org clan services. Only remote-builder is consumed for now
    # (inventory.nix); netif replaces the networking shim later.
    clanServices = {
      url = "github:external-systems/clanServices";
      inputs = {
        pkgs.follows = "org-pkgs";
        clan-core.follows = "clan-core";
      };
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      # Exposes debug.options / currentSystem.options, which nixd
      # (.vscode/settings.json) reads for flake-parts option hints.
      debug = true;

      systems = ["x86_64-linux"];

      imports = [
        # treefmt, docs and slides, lock-sync (checks, formatter, apps).
        inputs.org-pkgs.flakeModules.default
        inputs.clan-core.flakeModules.default
        (inputs.import-tree ./flake-parts)
      ];
    };
}
