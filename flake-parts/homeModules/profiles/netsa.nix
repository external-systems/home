{inputs, ...}: {
  # For Andrew's PCs
  flake.homeModules.profile-netsa = {
    config,
    pkgs,
    ...
  }: let
    # The Storage Box mount below; the aliases write into it.
    box = config.homeSpec.programs.storagebox.boxes.helsinki-box;
  in {
    imports = [inputs.modules.homeModules.default];
    config = {
      # homeSpec options
      homeSpec = {
        xdg.enable = true;
        # AI coding agents: the skills tree is wired into every enabled
        # agent. The base preset (core) plus every custom skill in
        # external-systems/skills (own-all). Add external picks from
        # skills.lib.selections here, e.g. `++ selections.anthropic`.
        agents = {
          kimi.enabled = true;
          pi.enabled = true;
          claude.enabled = true;
          opencode.enabled = true;
          machineContext = {
            repoOwner = "external-systems";
            repoName = "home";
            repoPath = "external-systems/home";
          };
          skills = {
            enabled = true;
            preset = "base";
            extraSources = inputs.modules.inputs.skills.lib.selections.own-all;
          };
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
            enable = false;
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
          vscode = {
            enable = true;
            # nixd's user-wide option source; the repo's own
            # .vscode/settings.json still wins inside it.
            nixdFlake = "${config.home.homeDirectory}/external-systems/home";
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
      # Personal aliases (modules' shell module ships none of these).
      programs.bash.shellAliases = {
        fabric-backup = "rsync -av --progress --delete kamrui-h1:/srv/minecraft/fabric/world/ ${box.mountPoint}/BACKUPS/minecraft/fabric/world/";
        fabric-backup-local = "rsync -av --progress --delete /srv/minecraft/fabric/world/ ${box.mountPoint}/Backups/fabric/world/";
        # Straight over ssh (the storagebox-helsinki-box alias), not the
        # mount.
        obsidian-pull = "rsync -avz storagebox-helsinki-box:/home/PRIVATE/OBSIDIAN/Main/ ~/Desktop/Main/";
        kubefetch-latest = ''nix run "https://flakehub.com/f/andrewthomaslee/kubefetch/*"'';
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
