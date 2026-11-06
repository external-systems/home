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
          # Gaming Mode user per machine; unset (nixos) boots the gaming
          # entry to the KDE login screen.
          machines.kamrui-h1.settings.user = "wife";
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
