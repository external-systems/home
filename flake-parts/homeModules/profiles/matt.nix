{self, ...}: {
  # For Matt — netsa-lite: the desktop basics with claude+pi and the
  # headroom proxy, without the rest of the dev-tooling stack. githubAuth
  # stays off (the default) until Matt has a GitHub PAT to provision;
  # turning it on later is one line
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
          pi.enabled = true;
          mcp.github.enable = false;
        };
        programs = {
          headroom = {
            enable = true;
            proxy.openaiApiUrl = "https://api.kimi.ai/coding/v1";
          };
          plasma-manager.enable = true;
          docker.enable = true;
          firefox.enable = true;
          ghostty.enable = true;
          git = {
            enable = true;
            userName = "matt";
            userEmail = "matt@netsam.com";
            # No signingKey here: ssh.clanKey makes the clan-generated
            # "user-ssh-matt" keypair the default signing key once
            # `clan vars generate` runs.
          };
          shell.enable = true;
          ssh = {
            enable = true;
            # Clan-generated per-user keypair (user-ssh-matt) — no manual
            # ssh-keygen needed.
            clanKey.enabled = true;
          };
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
