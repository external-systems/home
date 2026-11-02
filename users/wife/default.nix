{self, ...}: {
  nix.settings.allowed-users = ["wife"];
  users.users.wife = {
    isNormalUser = true;
    home = "/home/wife";
    description = "wife";
    extraGroups = [
      "wheel"
      "docker"
      "networkmanager"
      "audio"
      "libvirtd"
      "tty"
      "dialout"
      "video"
      "input"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOb4q9LWJR54SzRkfmsA5KWA5/SDEG853oFC8TVilCW/"
    ];
  };

  home-manager.users.wife = self.homeModules.profile-wife;
}
