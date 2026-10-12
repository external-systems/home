{self, ...}: {
  # For Andrew's PCs
  flake.homeModules.profile-netsa = {pkgs, ...}: {
    imports = [self.homeModules.default];
    config = {
      # homeSpec options
      homeSpec = {
        xdg.enable = true;
        # AI coding agents: the shared repo skill set (skills/ merged via
        # inputs.agents.lib.mkSkills) is wired into every enabled agent.
        agents = {
          skills.enabled = true;
          opencode.enabled = true;
          kimi.enabled = true;
          pi.enabled = true;
          claude.enabled = true;
          # GitHub MCP via the local stdio server + the shared clan-var PAT
          # (/run/secrets/vars/shared/github-mcp/pat, generator declared by
          # nixosModules/github-mcp when auth = "pat"). The default "oauth"
          # only works for opencode's browser flow and — worse — the PAT
          # generator is gated on "pat", so pi/kimi/claude's PAT wrapper had
          # no token at all under "oauth".
          mcp.github.auth = "pat";
        };
        programs = {
          # Headroom context-compression proxy (systemd user service on
          # 127.0.0.1:8787): every agent gets the headroom MCP server and
          # its provider traffic is rerouted (homeSpec.agents.mcp.headroom).
          # The OpenAI wire pipeline is pinned at kimi-code's managed
          # service so the kimi reroute (KIMI_CODE_BASE_URL) lands on the
          # right upstream; Anthropic keeps the default api.anthropic.com.
          headroom = {
            enable = true;
            proxy.openaiApiUrl = "https://api.kimi.ai/coding/v1";
          };
          plasma-manager.enable = true;
          docker.enable = true;
          devenv.enabled = true;
          firefox.enable = true;
          ghostty.enable = true;
          git.enable = true;
          k9s.enable = true;
          ksshaskpass.enable = true;
          media.enable = true;
          password-store.enable = true;
          shell.enable = true;
          ssh.enable = true;
          starship.enable = true;
          vscode.enable = true;
          openshell.enable = true;
          # Pairs with the NixOS service (kamrui-h1); manages
          # ~/.config/whisper-dictation/config.yaml. The Samsers KT06
          # bluetooth keyboard is pinned for push-to-talk (upstream
          # watches exactly one device); Super+Semicolon per its compact
          # layout.
          whisper-dictation = {
            enable = true;
            inputDevice = "Samsers KT06";
            hotkey = {
              modifiers = ["super"];
              key = "semicolon";
            };
          };
        };
      };
      # Home Options
      home.packages = with pkgs; [
        moscripts
        asciinema
        kalker
        freelens-bin
        gh
      ];
    };
  };
}
