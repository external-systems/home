# The gaming boot entry. The modules come with every machine
# (external-systems/modules nixosModules.default, through machine-type's
# base); the role switches them on and passes the per-machine settings
# from the inventory.
{
  interface = {lib, ...}: {
    options = {
      diskSwap = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = "Keep disk swap in the developer entry; false drops it there, as kubelet wants (hostSpec.system.developerSpecialisation.diskSwap).";
      };
      defaultEntry = lib.mkOption {
        type = lib.types.enum ["desktop" "gaming"];
        default = "desktop";
        example = "gaming";
        description = ''
          Default boot entry (hostSpec.system.gamingSpecialisation.defaultEntry):
          "desktop" boots the KDE login screen with Gaming Mode as the
          "gaming" entry; "gaming" boots Gaming Mode with the desktop as
          the "desktop" entry, as on a Steam Deck. Gaming Mode itself
          still needs gamingMode = true.
        '';
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
          inherit (settings) defaultEntry;
        };
        # The Kubernetes clan services will plug into this entry's
        # configuration hook (developerSpecialisation.configuration).
        developerSpecialisation = {
          enable = true;
          inherit (settings) diskSwap;
        };
        # Steam's defaults (GE-Proton) for every user, wherever Steam
        # runs: the default desktop and Gaming Mode.
        gaming = {
          steamConfig.enable = true;
          sharedLibraries = {
            enable = true;
            paths = settings.libraries;
          };
        };
        # gamingMode only boots Gaming Mode in the gaming entry.
        jovian =
          {inherit (settings) gamingMode outputs;}
          // lib.optionalAttrs (settings.user != null) {inherit (settings) user;};
      };
    };
  };
}
