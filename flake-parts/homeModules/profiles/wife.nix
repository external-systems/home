{inputs, ...}: {
  flake.homeModules.profile-wife = {...}: {
    imports = [inputs.modules.homeModules.default];
    config = {
      # homeSpec options
      homeSpec = {
        xdg.enable = true;
        programs = {
          plasma-manager.enable = true;
          firefox.enable = true;
          media.enable = true;
        };
      };

      # # Home Options
      # home.packages = with pkgs; [
      # ];
    };
  };
}
