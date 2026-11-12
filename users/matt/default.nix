{inputs, ...}: {
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

  # home-manager: the user's own environment.
  # For Matt — netsa-lite: the desktop basics with claude+pi and the
  # headroom proxy, without the rest of the dev-tooling stack. GitHub
  # auth comes from the per-user "github-matt" PAT clan var
  # (`clan vars generate <machine>` prompts for it).
  home-manager.users.matt = {pkgs, ...}: {
    imports = [
      inputs.modules.homeModules.default
      ../shared/office.nix
      ../shared/plasma.nix
    ];
    config = {
      # homeSpec options
      homeSpec = {
        xdg.enable = true;
        agents = {
          claude.enable = true;
          pi.enable = true;
          # Every custom skill in external-systems/skills, like netsa.
          skills.preset = "full";
          # GitHub MCP via the local stdio server and matt's PAT
          # ("github-matt"), the same token git and gh use.
          mcp.github.auth = "pat";
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
            # github.com over HTTPS and GH_TOKEN from the "github-matt"
            # PAT clan var.
            githubAuth.enabled = true;
          };
          shell.enable = true;
          ssh = {
            enable = true;
            # Clan-generated per-user keypair (user-ssh-matt) — no manual
            # ssh-keygen needed.
            clanKey.enabled = true;
          };
          starship.enable = true;
          # VSCodium's default theme; matt works by talking to Claude
          # (on by default), so the tooling it drives is all installed.
          vscodium = {
            enable = true;
            # Only the extensions below: nothing installed by accident.
            mutableExtensions = false;
            # Large, very readable letters in the editor and terminal.
            theme.font = {
              family = "'Atkinson Hyperlegible Mono', monospace";
              package = pkgs.atkinson-hyperlegible-mono;
              size = 16;
              lineHeight = 1.6;
            };
            tweaks.enable = true;
            remoteSsh.enable = true;
            todoTree.enable = true;
            githubActions.enable = true;
            languages = {
              nix.enable = true;
              yaml.enable = true;
              web.enable = true;
              markdown.enable = true;
            };
            kubernetes.enable = true;
            containers.enable = true;
          };
          # Same push-to-talk dictation setup as netsa.
          whisper-dictation = {
            enable = true;
            hotkey = {
              modifiers = ["super"];
              key = "semicolon";
            };
          };
        };
      };
      # Matt-only apps (Microsoft ones and Chromium); the rest is shared with netsa
      # (users/shared/office.nix).
      home.packages = with pkgs; [
        microsoft-edge
        chromium
        # OneDrive sync client and its tray GUI.
        onedrive
        onedrivegui
      ];
    };
  };
}
