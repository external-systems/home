{
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
  };
}
