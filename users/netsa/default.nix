{inputs, ...}: {
  nix.settings = {
    allowed-users = ["netsa"];
    # modules' hostSpec.services.nix trusts only root.
    trusted-users = ["netsa"];
  };
  users.users.netsa = {
    isNormalUser = true;
    home = "/home/netsa";
    description = "husband";
    extraGroups = [
      "docker"
      "wheel"
      "networkmanager"
      "audio"
      "libvirtd"
      "tty"
      "dialout"
      "video"
      "input"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOb4q9LWJR54SzRkfmsA5KWA5/SDEG853oFC8TVilCW/"
    ];
  };

  # home-manager: the user's own environment.
  # For Andrew's PCs
  home-manager.users.netsa = {
    config,
    pkgs,
    ...
  }: let
    # The Storage Box mount below; the aliases write into it.
    box = config.homeSpec.programs.storagebox.boxes.helsinki-box;
  in {
    imports = [
      inputs.modules.homeModules.default
      ../shared/office.nix
      ../shared/plasma.nix
    ];
    config = {
      # homeSpec options
      homeSpec = {
        xdg.enable = true;
        # AI coding agents: the skills tree is wired into every enabled
        # agent. The base preset (core) plus every custom skill in
        # external-systems/skills (own-all). Add external picks from
        # skills.lib.selections here, e.g. `++ selections.anthropic`.
        agents = {
          kimi.enable = true;
          pi.enable = true;
          claude.enable = true;
          opencode.enable = true;
          machineContext = {
            repoOwner = "external-systems";
            repoName = "home";
            repoPath = "external-systems/home";
          };
          skills.preset = "full";
          # GitHub MCP via the local stdio server + the per-user clan-var
          # PAT ("github-netsa", generator declared by nixosModules/git.nix
          # for any user with a token consumer). The default "oauth" only
          # works for opencode's browser flow and — worse — pi/kimi/claude's
          # PAT wrapper has no token at all under "oauth".
          mcp = {
            github.auth = "pat";
            artifacthub.enable = true;
            varlock-docs.enable = true;
          };
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
            # "user-ssh-netsa" keypair the default signing key once
            # generated. Upload the pub half to GitHub as a signing key to
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
          # Hetzner Storage Box helsinki-box: the main account (the id
          # lives in external-systems/secrets), its root mounted at
          # ~/storagebox/helsinki-box on login and reachable as the ssh
          # alias storagebox-helsinki-box. Key: the clan var
          # storagebox-ssh-netsa; install its public half on the box once
          # (command in modules' nixosModules/storagebox.nix).
          storagebox = {
            enabled = true;
            boxes.helsinki-box = {
              inherit (inputs.secrets.values.storageboxes.helsinki-box) user host port;
            };
          };
          # VSCodium with every language and the cluster tooling, the
          # built-in Red theme, a dyslexia-friendly font and the layout
          # tweaks. Claude and direnv are on by default.
          vscodium = {
            enable = true;
            theme = {
              color = "Red";
              # Atkinson Hyperlegible Mono (Braille Institute): letters
              # that can't be mistaken for each other (b/d, I/l/1, 0/O),
              # with extra line and letter spacing for easier reading.
              font = {
                family = "'Atkinson Hyperlegible Mono', monospace";
                package = pkgs.atkinson-hyperlegible-mono;
                size = 15;
                lineHeight = 1.6;
                letterSpacing = 0.5;
              };
            };
            tweaks.enable = true;
            remoteSsh.enable = true;
            envSpec.enable = true;
            todoTree.enable = true;
            githubActions.enable = true;
            languages = {
              nix = {
                enable = true;
                # nixd's user-wide option source; the repo's own
                # .vscode/settings.json still wins inside it.
                flake = "${config.home.homeDirectory}/external-systems/home";
              };
              go.enable = true;
              shell.enable = true;
              markdown.enable = true;
              python.enable = true;
              rust.enable = true;
              gleam.enable = true;
              zig.enable = true;
              web.enable = true;
              yaml.enable = true;
            };
            kubernetes.enable = true;
            containers.enable = true;
          };
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
      # netsa's own pinned apps on the shared panel (users/shared/plasma.nix).
      shared.plasma.launchers = [
        "applications:com.anthropic.Claude.desktop"
        "applications:zen.desktop"
        "applications:com.mitchellh.ghostty.desktop"
      ];
      # Personal aliases (modules' shell module ships none of these).
      programs.bash.shellAliases = {
        fabric-backup = "rsync -av --progress --delete kamrui-h1:/srv/minecraft/fabric/world/ ${box.mountPoint}/BACKUPS/minecraft/fabric/world/";
        fabric-backup-local = "rsync -av --progress --delete /srv/minecraft/fabric/world/ ${box.mountPoint}/Backups/fabric/world/";
        # Straight over ssh (the storagebox-helsinki-box alias), not the
        # mount.
        obsidian-pull = "rsync -avz storagebox-helsinki-box:/home/PRIVATE/OBSIDIAN/Main/ ~/Desktop/Main/";
        kubefetch-latest = ''nix run "https://flakehub.com/f/andrewthomaslee/kubefetch/*"'';
      };
      # Home Options. Personal tools only: the shared dev apps come from
      # the dev tag (clanServices/tags/dev.nix), the nix toolchain from
      # vscodium.languages.nix.
      home.packages = with pkgs; [
        moscripts
        asciinema
        kalker
        # DualSense controller settings (lightbar, battery, triggers).
        dualsensectl
        # Only netsa gets Tor Browser; it left the pc role's system apps.
        tor-browser
      ];
    };
  };
}
