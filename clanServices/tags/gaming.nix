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
          # Nothing to stop yet: the developer entry runs no Kubernetes
          # services. When the Kubernetes clan services get their own
          # off-switch, set it here (gamingSpecialisation.configuration).
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
