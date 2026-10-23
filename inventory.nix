{customLib}: let
  inherit (customLib) relativeToRoot;
in {
  meta = {
    name = "home";
    description = "monorepo";
    domain = "andrewlee.fun";
  };

  machines = {
    # Andrew's PCs
    nixos = {
      deploy.targetHost = "root@nixos";
      tags = ["pc" "intel" "virt" "lan" "dev" "netsa" "wife"];
    };
    kamrui-h1 = {
      deploy.targetHost = "root@kamrui-h1";
      tags = ["pc" "amd" "virt" "wan" "dev" "netsa" "wife" "matt"];
    };
    ghost = {
      deploy.targetHost = "root@ghost";
      tags = ["pc" "intel" "virt" "wan" "dev" "netsa"];
    };
    # Wife's PCs
    hp-notebook = {
      deploy.targetHost = "root@192.168.1.246";
      tags = ["pc" "intel" "wan" "wife"];
    };
    # Shared PCs
    beelink = {
      deploy.targetHost = "root@192.168.50.2";
      tags = ["pc" "amd" "virt" "wan" "dev" "netsa" "matt"];
    };

    nixos-installer.tags = ["iso"];
  };

  # --- Clan Services --- #
  instances = {
    machine-type = {
      module.input = "self";
      module.name = "@andrewthomaslee/machine-type";
      roles = {
        pc.tags.pc = {};
        iso.tags.iso = {};
      };
    };

    tags = {
      module.input = "self";
      module.name = "@andrewthomaslee/tags";
      roles = {
        amd.tags.amd = {};
        dev.tags.dev = {};
        intel.tags.intel = {};
        lan.tags.lan = {};
        virt.tags.virt = {};
        wan.tags.wan = {};
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
        extraModules = [(relativeToRoot "users/root")];
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
        extraModules = [(relativeToRoot "users/netsa")];
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
        extraModules = [(relativeToRoot "users/wife")];
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
        extraModules = [(relativeToRoot "users/matt")];
      };
    };

    trusted-nix-caches.roles.default.tags.all = {};
  };
}
