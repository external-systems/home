# Clan inventory. Deploy targets and builder addresses come from the
# values flake (`secrets`): not-secrets placeholders publicly, the real
# external-systems/secrets at deploy time (see flake.nix).
{
  lib,
  secrets,
}: let
  inherit (secrets) hosts;

  # euc-hel-0 is the former borg helsinki-manager-1 (same Hetzner Robot
  # server, reinstalled into this fleet). Its values still live under
  # the old name in external-systems/secrets and not-secrets; rename
  # them there, then here.
  eucHel0 = hosts.helsinki-manager-1;
  eucHel0Address = lib.head (lib.splitString "/" (lib.head eucHel0.links.public.ipv4));
in {
  meta = {
    name = "home";
    description = "monorepo";
    domain = "andrewlee.fun";
  };

  machines = {
    # Andrew's PCs
    nixos = {
      deploy.targetHost = hosts.nixos.targetHost;
      tags = ["pc" "intel" "virt" "dev" "netsa" "wife"];
    };
    kamrui-h1 = {
      deploy.targetHost = hosts.kamrui-h1.targetHost;
      tags = ["pc" "amd" "virt" "dev" "netsa" "wife" "matt"];
    };
    ghost = {
      deploy.targetHost = hosts.ghost.targetHost;
      tags = ["pc" "intel" "virt" "dev" "netsa"];
    };
    # Wife's PCs
    hp-notebook = {
      deploy.targetHost = hosts.hp-notebook.targetHost;
      tags = ["pc" "intel" "wife"];
    };
    # Shared PCs
    beelink = {
      deploy.targetHost = hosts.beelink.targetHost;
      tags = ["pc" "amd" "virt" "dev" "netsa" "matt"];
    };

    # Servers
    # Hetzner Robot (Xeon W-2295): remote builder and CI build box.
    euc-hel-0 = {
      deploy.targetHost = "root@${eucHel0Address}";
      # Headless: the intel tag only adds GPU media drivers.
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
        amd.tags.amd = {};
        dev.tags.dev = {};
        intel.tags.intel = {};
        virt.tags.virt = {};
      };
    };

    # --- Remote builds (nixbuild.net-style) --- #
    # Every PC sends builds to euc-hel-0; CI uses the instance's CI key.
    remote-builder = {
      module = {
        input = "self";
        name = "@andrewthomaslee/remote-builder";
      };
      roles = {
        server.machines.euc-hel-0.settings.address = eucHel0Address;
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
