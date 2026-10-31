{inputs, ...}: {
  flake.homeModules.profile-root = {
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
