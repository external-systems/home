# The gaming boot entry. The modules come with every machine
# (external-systems/modules nixosModules.default, through machine-type's
# base); the role switches them on and passes the per-machine settings
# from the inventory.
{
  interface = {lib, ...}: {
    options = {
      diskSwap = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = "Use disk swap only in the gaming entry (hostSpec.system.gamingSpecialisation.diskSwap).";
      };
      gamingMode = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          Boot the gaming entry into Steam Gaming Mode
          (hostSpec.system.jovian.gamingMode), logged in as `user`.
          Off boots it to the KDE login screen.
        '';
      };
      user = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "wife";
        description = ''
          Override for the user Gaming Mode logs in as. null uses the
          dedicated, locked "gamer" user (hostSpec.system.gaming.user),
          which is then declared automatically.
        '';
      };
      outputs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["DP-1"];
        description = ''
          Display connectors Gaming Mode prefers, in order
          (hostSpec.system.jovian.outputs); any other output is the
          fallback. Find them with `kscreen-doctor -o`.
        '';
      };
      libraries = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["/srv/games"];
        example = ["/mnt/steam" "/mnt/games2"];
        description = ''
          Shared Steam library roots, one per disk
          (hostSpec.system.gaming.sharedLibraries.paths): game files are
          downloaded once and shared by every user, Proton prefixes stay
          per user. Each path must sit under a mount point from the
          machine's disko.nix; the default lives on the root filesystem.
        '';
      };
    };
  };

  perInstance = {settings, ...}: {
    nixosModule = {lib, ...}: {
      hostSpec.system = {
        gamingSpecialisation = {
          enable = true;
          inherit (settings) diskSwap;
          # Stop what the Kubernetes clan services (external-systems/
          # clanServices k3s, rke2, routed-fabric) enable: HAProxy, k3s,
          # rke2 and every FRR daemon. Networking (netif/IfState,
          # WireGuard, dummy interfaces) stays as the machine defines it.
          configuration = {options, ...}: let
            # Every FRR daemon the nixpkgs module offers, read from its
            # options so new daemons are covered too. Removed options
            # (zebra, always on with FRR) are invisible stubs that reject
            # any definition, so they are skipped.
            frrDaemons = lib.filter (
              name: let
                opt = options.services.frr.${name};
              in
                opt ? enable && (opt.enable.visible or true) != false
            ) (lib.attrNames options.services.frr);
          in {
            services = {
              haproxy.enable = lib.mkForce false;
              k3s.enable = lib.mkForce false;
              rke2.enable = lib.mkForce false;
              frr = lib.genAttrs frrDaemons (_: {enable = lib.mkForce false;});
            };
          };
        };
        gaming.sharedLibraries = {
          enable = true;
          paths = settings.libraries;
        };
        # Only takes effect in the gaming entry, where jovian is on.
        jovian =
          {inherit (settings) gamingMode outputs;}
          // lib.optionalAttrs (settings.user != null) {inherit (settings) user;};
      };
    };
  };
}
