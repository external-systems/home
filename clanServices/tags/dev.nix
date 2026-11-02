{lib, ...}: {
  config = {
    hostSpec = {
      services = {
        docker.enable = true;
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
