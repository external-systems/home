{lib, ...}: {
  config = {
    hostSpec = {
      services = {
        docker.enable = true;
        # The id is already public: it names the shared vars generator
        # (vars/shared/storagebox-ssh-<id>), so it must match to keep the
        # deployed key. Move it to external-systems/secrets with the
        # generator rename.
        storagebox = {
          enable = true;
          boxUser = "u488514";
        };
        nix.enable = true;
        nix-ld.enable = true;
      };
    };

    # nixos options
    security.sudo.wheelNeedsPassword = false;
    boot.binfmt.emulatedSystems = ["aarch64-linux"];

    specialisation = {
      warp.configuration = {
        hostSpec.networking = {
          tailscale = {
            enable = lib.mkForce false;
            systray = lib.mkForce false;
          };
          warp.enable = lib.mkForce true;
        };
      };
      tailscale.configuration = {
        hostSpec = {
          networking = {
            tailscale = {
              enable = lib.mkForce true;
              systray = lib.mkForce true;
            };
            warp.enable = lib.mkForce false;
          };
        };
      };
    };
  };
}
