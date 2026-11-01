{self, ...}: {
  hostSpec.services.onepassword = {
    enable = true;
    polkitPolicyOwners = ["netsa"];
  };
  nix.settings = {
    allowed-users = ["netsa"];
    # modules' hostSpec.services.nix trusts only root.
    trusted-users = ["netsa"];
  };
  users.users.netsa = {
    isNormalUser = true;
    home = "/home/netsa";
    description = "husband";
    extraGroups = [
      "docker"
      "wheel"
      "networkmanager"
      "audio"
      "libvirtd"
      "tty"
      "dialout"
      "video"
      "storage-users"
      "input"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOb4q9LWJR54SzRkfmsA5KWA5/SDEG853oFC8TVilCW/"
    ];
  };

  home-manager.users.netsa = self.homeModules.profile-netsa;
}
