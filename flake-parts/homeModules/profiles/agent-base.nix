{self, ...}: {
  # PORTABLE agent user environment — the reusable core of the agent
  # sandbox profiles. Carries everything user-level an agent sandbox
  # needs for agentic coding: the shell/prompt, git/gh identity, the
  # language toolchains (uv/python, go, bun) and the CLI toolbelt
  # (incl. the agent CLIs themselves), all as ordinary home-manager
  # config so any consumer gets the same environment.
  #
  # Consumers (flavor modules) compose this base and add their
  # platform's quirks:
  #  - homeModules.profile-agent (profiles/agent.nix): the OpenShell
  #    code-agent OCI image — static identity (uid 1000, /home/agent),
  #    no systemd, env via /etc/profile instead of HM session
  #    variables, [sandbox] prompt marker, /etc/profile sourcing from
  #    bashrc (the supervisor spawns `bash -i` with a scrubbed env).
  #  - future NixOS/kubevirt agent sandboxes: import this base in a
  #    profile (or directly as home-manager.users.<name>) and let HM
  #    run normally — systemd.user and session variables ON, no
  #    /etc/profile sourcing needed (login shells read it natively),
  #    hostname in the prompt instead of the [sandbox] marker.
  #
  # Like all profile-* modules this is excluded from homeModules.
  # default's auto-import (flake-parts/default.nix filter) — fleet
  # users never get it unless they ask.
  flake.homeModules.profile-agent-base = {pkgs, ...}: {
    # The fleet's shared starship config (homeModules.starship): pure
    # HM options, no osConfig/NixOS coupling, so it composes with any
    # consumer. HM initializes starship from the package's STORE path
    # (mkOrder 1900, end of .bashrc), so it works even where home-path
    # is not on PATH.
    imports = [self.homeModules.starship];
    homeSpec.programs.starship.enable = true;

    # No container runtime exists in any agent sandbox — in the
    # OpenShell microVM docker/podman are outright impossible (user
    # namespaces are seccomp-blocked, no root, no /var/lib; see
    # documentation/docs/openshell/index.md §5). The OCI rootfs still
    # carries a baked /.dockerenv (host `docker create` image-prep
    # artifact), which makes starship's `container` module print a
    # bogus "⬢ [Docker]" on every prompt, and `docker_context` would
    # fire on Dockerfiles in agent workdirs — disable both.
    programs.starship.settings = {
      container.disabled = true;
      docker_context.disabled = true;
    };

    programs = {
      bash = {
        enable = true;
        # Login shells chain into .bashrc so they get the same
        # interactive setup as non-login interactive shells.
        profileExtra = ''
          if [ -r "$HOME/.bashrc" ]; then
            . "$HOME/.bashrc"
          fi
        '';
        shellAliases = {
          ll = "ls -alF --color=auto";
          la = "ls -A --color=auto";
          l = "ls -CF --color=auto";
          grep = "grep --color=auto";
          # nix's getifaddrs heuristic reports "no Internet" inside
          # VMs/sandboxes and silently disables substitution — force
          # it back on for interactive use (scripts must pass the flag
          # themselves; aliases don't reach them).
          nix = "nix --option substitute true";
        };
        historyControl = ["ignoreboth" "erasedups"];
        historySize = 10000;
        historyFileSize = 20000;
      };

      # Git identity + github.com credential helper, previously baked
      # as /etc/gitconfig in the OCI image — user-level HM config is
      # what makes it reusable on NixOS hosts. The helper feeds git
      # the provider-injected $GITHUB_TOKEN (OpenShell substitutes the
      # real token at egress); with no token set it yields empty
      # credentials and git falls back to its normal behavior.
      git = {
        enable = true;
        settings = {
          user = {
            name = "andrewthomaslee-agent";
            email = "andrewthomaslee-agent@users.noreply.github.com";
          };
          init.defaultBranch = "main";
          credential."https://github.com".helper = "!f() { echo username=x-access-token; echo password=$GITHUB_TOKEN; }; f";
        };
      };

      # gh authenticates from the same provider-injected $GITHUB_TOKEN
      # (GH_TOKEN/GITHUB_TOKEN env is read natively); no hosts.yml.
      # gitCredentialHelper defaults ON and would replace the scoped
      # env-token helper above with `gh auth git-credential` — keep it
      # off (the env-token helper needs no gh auth state).
      gh = {
        enable = true;
        gitCredentialHelper.enable = false;
      };

      # Go: the module's env/sessionVariables (GOPATH & co.) are left
      # unset — the defaults (~/go) are right everywhere; telemetry
      # off via the static modefile (works without activation).
      go = {
        enable = true;
        telemetry.mode = "off";
      };

      # bun runtime for TS/JS agent work.
      bun.enable = true;

      # uv + baked uv.toml. Carries over the
      # python-downloads/python-preference settings of the repo's old
      # homeModules/uv.nix (deleted in f3eef10 in the "packages move to
      # project devshells" trim — a fleet trim, not a technical
      # problem); link-mode is deliberately NOT pinned (hardlinks are
      # fine on both target platforms). NOTE: programs.uv's
      # python.versions / tool.packages options are activation-time
      # (uv python/tool install) — they only work where HM activation
      # actually runs (NixOS hosts), NOT in the OCI image.
      uv = {
        enable = true;
        settings = {
          # The nixpkgs python3 (home.packages below) is the only
          # interpreter: managed CPython downloads (foreign FHS
          # binaries) are off — other versions come via nix.
          python-downloads = "never";
          python-preference = "only-system";
          # Wheels only BY DEFAULT: sdists that compile need a C
          # toolchain — fail fast instead of a doomed compile. Escape
          # hatch: CLI flags override the config (`nix shell nixpkgs#gcc
          # -c uv pip install --only-binary :none: …`).
          no-build = true;
          pip.only-binary = [":all:"];
        };
      };
    };

    # The agent toolbelt. In the OCI image these reach PATH via the
    # HM home-path merged into the image's baseTools buildEnv (see
    # hmAgent in flake-parts/ociImages/code-agent.nix); on NixOS they
    # land in the normal HM profile path.
    home.packages = with pkgs; [
      jq
      yq
      python3
      ripgrep
      fd
      sd
      tmux
      less
      curl
      wget
      unzip
      zstd
      file
      which
      dnsutils
      # no rsync: in an OpenShell sandbox its receiver is denied by the
      # supervisor's filesystem mediation (change_dir EACCES even for
      # /tmp→/tmp — verified 2026-10); hosts still get rsync system-wide
      # via clanServices/machine-type (environment.systemPackages).
      shellcheck
      shfmt
      kubectl
      kubernetes-helm
      # Repo workflow: nix language server + the lint trio (the repo's
      # checks.lint gate runs these in-sandbox).
      nixd
      alejandra
      statix
      deadnix
      # The clan CLI: baked because it can never be obtained in-sandbox
      # — clan-cli's clan-runtime dependency builds with a nested
      # `nix flake update --store ./.` inside the builder, which the
      # sandbox supervisor's egress and the overlayfs rename assert
      # cannot support (verified: exit 134 in-sandbox).
      clan-cli
      # AI coding agents (from the llm-agents flake input, see
      # overlays/default.nix).
      pi-coding-agent
      kimi-code
      claude-code
    ];
  };
}
