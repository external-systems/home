{self, ...}: {
  nix.settings.allowed-users = ["matt"];
  users.users.matt = {
    isNormalUser = true;
    home = "/home/matt";
    description = "matt";
    # Deliberately smaller than netsa/wife: no libvirtd/storage.
    extraGroups = [
      "wheel"
      "docker"
      "networkmanager"
      "audio"
      "video"
      "input"
    ];
    # TODO: No SSH authorizedKeys yet — add Matt's pubkey here when he has one.
  };

  home-manager.users.matt = self.homeModules.profile-matt;
}
