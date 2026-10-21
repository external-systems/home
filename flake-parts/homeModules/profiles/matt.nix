{self, ...}: {
  # For Matt — netsa-lite: the desktop basics without the agent/headroom/
  # dev-tooling stack. githubAuth stays off (the default) until Matt has a
  # GitHub PAT to provision; turning it on later is one line
  # (git.githubAuth.enabled = true) + `clan vars generate <machine>`.
  flake.homeModules.profile-matt = {...}: {
    imports = [self.homeModules.default];
    config = {
      # homeSpec options
      homeSpec = {
        xdg.enable = true;
        # Claude only (no opencode/pi/kimi). The github MCP is disabled: it
        # would declare the "github-matt" PAT generator and prompt for a
        # token Matt doesn't have — enable mcp.github once he does.
        agents = {
          skills.enabled = true;
          claude.enabled = true;
          mcp.github.enable = false;
        };
        programs = {
          plasma-manager.enable = true;
          docker.enable = true;
          firefox.enable = true;
          ghostty.enable = true;
          git = {
            enable = true;
            # TODO: Matt's commit identity is set, but signing stays off
            # until he has an SSH key of his own (signingKey = null).
            userName = "matt";
            userEmail = "matt@netsam.com";
            signingKey = null;
          };
          shell.enable = true;
          ssh.enable = true;
          starship.enable = true;
          vscode.enable = true;
          # Same push-to-talk dictation setup as netsa (NixOS service runs
          # on kamrui-h1).
          whisper-dictation = {
            enable = true;
            hotkey = {
              modifiers = ["super"];
              key = "semicolon";
            };
          };
        };
      };
    };
  };
}
