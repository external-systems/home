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
      gamingEntry = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = ''
          Whether the machine has the gaming entry
          (hostSpec.system.gamingSpecialisation.gamingEntry). false
          leaves the desktop and developer entries: one Steam client, no
          Gaming Mode and no `gamer` user, for a desktop several people
          use. Needs defaultEntry = "desktop".
        '';
      };
      games = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              example = "Overwatch";
              description = "The game's name, for the launcher script's messages.";
            };
            compatTool = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "GE-Proton";
              description = ''
                Internal name of the compatibility tool for this game
                ("GE-Proton", "proton_experimental", ...). It beats
                Valve's own pick for the game, which the global default
                does not. null keeps Steam's choice.
              '';
            };
            env = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = {};
              example = {PROTON_LOCAL_SHADER_CACHE = "1";};
              description = "Environment variables the game starts with.";
            };
            wrappers = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              example = ["gamemoderun"];
              description = "Commands the game runs under, outermost first.";
            };
            args = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              example = ["-dx12"];
              description = "Arguments after the game's own command.";
            };
          };
        });
        default = {};
        example = {
          "2357570" = {
            name = "Overwatch";
            compatTool = "GE-Proton";
            wrappers = ["gamemoderun"];
          };
        };
        description = ''
          Per-game Steam settings, keyed by Steam App ID (the number in
          the game's store URL), for every user on the machine
          (programs.steam.config.apps, steam-config-nix). They replace
          launch options typed in Steam for that game; a change applies
          at the game's next start.
        '';
      };
    };
  };

  perInstance = {settings, ...}: {
    nixosModule = {lib, ...}: {
      hostSpec.system = {
        gamingSpecialisation = {
          enable = true;
          inherit (settings) defaultEntry gamingEntry;
        };
        # The Kubernetes clan services will plug into this entry's
        # configuration hook (developerSpecialisation.configuration).
        developerSpecialisation = {
          enable = true;
          inherit (settings) diskSwap;
        };
        # Steam's defaults (GE-Proton) for every user, wherever Steam
        # runs: the default desktop and Gaming Mode. Every user keeps a
        # Steam library of their own; games and shader caches are shared
        # by reflink copies (steam-copy-game, steam-shader-sync).
        gaming = {
          steamConfig.enable = true;
          steamSharing.enable = true;
        };
        # gamingMode only boots Gaming Mode in the gaming entry.
        jovian =
          {inherit (settings) gamingMode outputs;}
          // lib.optionalAttrs (settings.user != null) {inherit (settings) user;};
      };
      # Inventory settings are plain data: compatTool is a tool's
      # internal name, never a package.
      programs.steam.config.apps = lib.mapAttrs (_: game:
        {inherit (game) name env wrappers args;}
        // lib.optionalAttrs (game.compatTool != null) {inherit (game) compatTool;})
      settings.games;
    };
  };
}
