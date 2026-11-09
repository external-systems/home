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
  # headroom proxy, without the rest of the dev-tooling stack. githubAuth
  # stays off (the default) until Matt has a GitHub PAT to provision;
  # turning it on later is one line
  # (git.githubAuth.enabled = true) + `clan vars generate <machine>`.
  home-manager.users.matt = {pkgs, ...}: {
    imports = [inputs.modules.homeModules.default];
    config = {
      # homeSpec options
      homeSpec = {
        xdg.enable = true;
        # Claude only (no opencode/pi/kimi). The github MCP is disabled: it
        # would declare the "github-matt" PAT generator and prompt for a
        # token Matt doesn't have — enable mcp.github once he does.
        agents = {
          claude.enable = true;
          pi.enable = true;
          # Every custom skill in external-systems/skills, like netsa.
          skills.preset = "full";
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
      # The Microsoft apps and fonts matt knows from Windows.
      fonts.fontconfig.enable = true;
      home.packages = with pkgs; [
        teams-for-linux # Microsoft Teams
        microsoft-edge
        # Word/Excel/PowerPoint look-alike with the best .docx/.xlsx/.pptx
        # fidelity.
        onlyoffice-desktopeditors
        # OneDrive sync client and its tray GUI.
        onedrive
        onedrivegui
        powershell
        # Arial, Times New Roman, Verdana, ... and Calibri, Cambria,
        # Consolas, ...: Office documents render with their own fonts.
        corefonts
        vista-fonts
      ];
    };
  };
}
