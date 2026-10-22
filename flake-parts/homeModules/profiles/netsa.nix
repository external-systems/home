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
          kimi.enabled = true;
          pi.enabled = true;
          claude.enabled = true;
          # GitHub MCP via the local stdio server + the per-user clan-var
          # PAT ("github-netsa", generator declared by nixosModules/git.nix
          # for any user with a token consumer). The default "oauth" only
          # works for opencode's browser flow and — worse — pi/kimi/claude's
          # PAT wrapper has no token at all under "oauth".
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
          git = {
            enable = true;
            userName = "andrewthomaslee";
            userEmail = "andrew@external.systems";
            # No signingKey here: ssh.clanKey makes the clan-generated
            # "user-ssh-netsa" pubkey the default signing key once
            # generated. Upload that pub to GitHub as a signing key to
            # keep the verified badge.
            # Declarative github.com auth (HTTPS credential helper +
            # GH_TOKEN) via the per-user "github-netsa" clan var — the same
            # token feeds the github MCP wrapper. The deployed path is
            # supplied by nixosModules/git.nix; githubAuth is off by
            # default for every other user.
            githubAuth.enabled = true;
          };
          k9s.enable = true;
          ksshaskpass.enable = true;
          media.enable = true;
          password-store.enable = true;
          shell.enable = true;
          ssh = {
            enable = true;
            # Clan-generated per-user keypair (user-ssh-netsa): git's
            # default signing key once generated. The default
            # ~/.ssh/id_ed25519 stays untouched.
            clanKey.enabled = true;
          };
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
            # inputDevice = "Samsers KT06";
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
        python3Minimal
        freelens-bin
        nixd
        alejandra
        statix
        deadnix
        nixfmt-rs
        argocd
        flux9s
        fluxcd
        mongodb-compass
        pgadmin4-desktopmode
      ];
    };
  };
}
