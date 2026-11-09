# Clan inventory. The clan domain, deploy targets and builder addresses
# come from the values flake (`secrets`, the private external-systems/secrets; see
# flake.nix).
{
  lib,
  secrets,
}: let
  inherit (secrets) hosts;
in {
  meta = {
    name = "home";
    description = "monorepo";
    domain = secrets.domains.primary;
  };

  # Tags, in order: machine type (pc/server), purpose (dev, gaming), users
  # (netsa, wife, matt). Hardware is not a tag: GPUs, Bluetooth and Wi-Fi
  # set themselves up from each machine's facter.json
  # (clanServices/tags/default.nix).
  machines = {
    # Andrew's PCs
    nixos = {
      deploy.targetHost = hosts.nixos.targetHost;
      tags = ["pc" "dev" "gaming" "netsa" "wife"];
    };
    kamrui-h1 = {
      deploy.targetHost = hosts.kamrui-h1.targetHost;
      tags = ["pc" "dev" "gaming" "netsa" "wife"];
    };
    ghost = {
      deploy.targetHost = hosts.ghost.targetHost;
      tags = ["pc" "dev" "netsa"];
    };
    # Wife's PCs
    hp-notebook = {
      deploy.targetHost = hosts.hp-notebook.targetHost;
      tags = ["pc" "wife"];
    };
    # Shared PCs
    beelink = {
      deploy.targetHost = hosts.beelink.targetHost;
      tags = ["pc" "dev" "netsa" "matt"];
    };

    # Servers
    # Hetzner Robot (Xeon W-2295): remote builder and CI build box.
    euc-hel-0 = {
      deploy.targetHost = hosts.euc-hel-0.targetHost;
      tags = ["server"];
    };
  };

  # --- Clan Services --- #
  instances = {
    machine-type = {
      module = {
        input = "self";
        name = "@andrewthomaslee/machine-type";
      };
      roles = {
        pc.tags.pc = {};
        server.tags.server = {};
      };
    };

    tags = {
      module = {
        input = "self";
        name = "@andrewthomaslee/tags";
      };
      roles = {
        dev.tags.dev = {};
        gaming = {
          tags.gaming = {};
          # kamrui-h1 is a KDE desktop for netsa and wife: Steam in each
          # one's own session, no Gaming Mode (that is for the Steam
          # Deck), and the developer entry.
          machines.kamrui-h1.settings = {
            gamingEntry = false;
            # Valve picks Proton Stable for these, which beats the
            # global GE-Proton default; a per-game tool beats Valve's.
            games = {
              "2357570" = {
                name = "Overwatch";
                compatTool = "GE-Proton";
                # Compiled shaders kept per game, with a 10 GB Mesa
                # cache instead of the ~1 GB default.
                env.PROTON_LOCAL_SHADER_CACHE = "1";
                wrappers = ["gamemoderun"];
              };
              "632360" = {
                name = "Risk of Rain 2";
                compatTool = "GE-Proton";
              };
            };
          };
        };
      };
    };

    # --- Remote builds (nixbuild.net-style) --- #
    # Every PC sends builds to euc-hel-0; CI uses the instance's CI key.
    remote-builder = {
      module = {
        input = "clanServices";
        name = "remote-builder";
      };
      roles = {
        # The builder's address is its deploy host, without the user.
        server.machines.euc-hel-0.settings.address = lib.last (lib.splitString "@" hosts.euc-hel-0.targetHost);
        client.tags.pc = {};
      };
    };

    # --- Create Users --- #
    # Admin
    root = {
      module.name = "users";
      roles.default = {
        settings = {
          user = "root";
          prompt = false;
        };
        tags = ["all"];
        extraModules = [./users/root];
      };
    };

    # Default User
    netsa = {
      module.name = "users";
      roles.default = {
        settings = {
          user = "netsa";
          share = true;
        };
        tags = ["netsa"];
        extraModules = [./users/netsa];
      };
    };

    # Default Wife
    wife = {
      module.name = "users";
      roles.default = {
        settings = {
          user = "wife";
          share = true;
        };
        tags = ["wife"];
        extraModules = [./users/wife];
      };
    };

    # Matt
    matt = {
      module.name = "users";
      roles.default = {
        settings = {
          user = "matt";
          share = true;
        };
        tags = ["matt"];
        extraModules = [./users/matt];
      };
    };

    trusted-nix-caches.roles.default.tags.all = {};
  };
}
