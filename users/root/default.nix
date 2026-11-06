{inputs, ...}: {
  nix.settings.allowed-users = ["root"];
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOb4q9LWJR54SzRkfmsA5KWA5/SDEG853oFC8TVilCW/"
  ];

  # home-manager: the user's own environment.
  home-manager.users.root = {
    imports = [inputs.modules.homeModules.default];
    config.homeSpec = {
      xdg.enable = true;
      programs = {
        shell.enable = true;
        ssh.enable = true;
        starship.enable = true;
        k9s.enable = true;
      };
    };
  };
}
