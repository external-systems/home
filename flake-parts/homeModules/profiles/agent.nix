{self, ...}: {
  # Minimal home-manager profile for the OpenShell code-agent sandbox
  # image's `agent` user (uid 1000). Unlike the other profile-* modules
  # this one is NOT wired to a NixOS host user and does NOT import
  # homeModules.default — the sandbox evaluates it standalone
  # (homeManagerConfiguration) at image-build time in
  # flake-parts/ociImages/code-agent.nix and bakes the generated
  # home-files into both $HOME roots (/home/agent and /sandbox).
  # Home-manager here is strictly a dotfile generator: no activation,
  # no systemd, no runtime `home-manager switch` in the sandbox.
  flake.homeModules.profile-agent = {lib, ...}: {
    # The fleet's shared starship config (homeModules.starship): pure
    # HM options, no osConfig/NixOS coupling, so it imports cleanly
    # into this standalone eval. HM initializes starship from the
    # package's STORE path at mkOrder 1900 (end of .bashrc), so the
    # binary works with no home-path on PATH — the store reference
    # also pulls starship into the image closure automatically.
    imports = [self.homeModules.starship];

    home = {
      username = "agent";
      homeDirectory = "/home/agent";
      # Pin to the home-manager input's release (release.json).
      stateVersion = "26.11";
    };

    # No systemd in the sandbox (no systemd PID 1, no user manager) —
    # keep HM's systemd-user artifacts (tray.target, environment.d
    # conf) out of the image entirely.
    systemd.user.enable = false;
    # The image's env comes from /etc/profile + the create-time --env
    # set, so HM session variables would only duplicate it — and HM's
    # i18n module seeds LOCALE_ARCHIVE_2_27 by default, which would
    # drag the ~200MB glibcLocales package into the image closure via
    # hm-session-vars.sh for zero benefit (the old image never had it).
    home.sessionVariables = lib.mkForce {};

    # The image needs the generated FILES, not manuals — and the manpage
    # derivation build fails under the in-sandbox FS policy.
    manual = {
      manpages.enable = false;
      html.enable = false;
      json.enable = false;
    };
    news.display = "silent";

    programs = {
      bash = {
        enable = true;
        # LOAD-BEARING: interactive ssh sessions into the sandbox are
        # `bash -i` — a NON-login shell that reads ONLY ~/.bashrc. HM's
        # own init does not source /etc/profile, so do it here: the
        # image's /etc/profile is idempotent and POSIX-safe, and it is
        # what restores PATH/wheel-deps/nix-ld/terminfo env under the
        # supervisor's scrubbed (env_clear) process env.
        initExtra = ''
          # shellcheck source=/etc/profile
          if [ -r /etc/profile ]; then
            . /etc/profile
          fi

          # TERM fallback: ssh forwards the client's TERM verbatim via the
          # pty request; fall back when it has no entry in the baked
          # terminfo db (xterm-256color is always present).
          if [ -n "''${TERM:-}" ] && ! infocmp "$TERM" >/dev/null 2>&1; then
            export TERM=xterm-256color
          fi
        '';
        # Login shells (`bash -lc` — remote commands, editor server
        # bootstraps) read /etc/profile themselves; chain into .bashrc so
        # they get the same interactive setup as `bash -i` sessions.
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
          # nix's getifaddrs heuristic reports "no Internet" in the
          # microVM and silently disables substitution — force it back
          # on for interactive use (scripts must pass the flag
          # themselves; aliases don't reach them).
          nix = "nix --option substitute true";
        };
        historyControl = ["ignoreboth" "erasedups"];
        historySize = 10000;
        historyFileSize = 20000;
      };

      # Starship owns the prompt (no static PS1 above): the shared
      # settings plus sandbox deltas — a literal [sandbox] marker (the
      # machine you are typing into is a disposable microVM, not the
      # host) instead of the meaningless container hostname. Glyph
      # rendering depends on the CLIENT's font (nerd fonts), same as on
      # the NixOS hosts.
      starship.settings = {
        format = "[\\[sandbox\\]](bold purple) $all";
        hostname.disabled = true;
      };

      # uv: binary via home.packages (home-path is merged into baseTools)
      # and a baked uv.toml enforcing the sandbox briefing's Python rules
      # (wheels only — no C toolchain ships in the image; the baked
      # nixpkgs python3 is the only interpreter). Carries over the
      # python-downloads/python-preference settings of the repo's old
      # homeModules/uv.nix (deleted in f3eef10 in the "packages move to
      # project devshells" trim — a fleet trim, not a technical problem);
      # link-mode is deliberately NOT pinned — hardlinks between the uv
      # cache and projects under /sandbox are verified working, and copy
      # mode would waste the 32GiB overlay. NOTE: programs.uv's
      # python.versions / tool.packages options are activation-time
      # (uv python/tool install) and are DEAD here — the sandbox never
      # runs HM activation.
      uv = {
        enable = true;
        settings = {
          # The baked nixpkgs python3 is the only interpreter: managed
          # CPython downloads (foreign FHS binaries riding the nix-ld
          # shim) are off — other versions come via nix substitution
          # (`nix run --option substitute true nixpkgs#python314`).
          python-downloads = "never";
          python-preference = "only-system";
          # Wheels only BY DEFAULT: sdists that compile cannot build
          # in-sandbox (no C toolchain) — fail fast instead of a doomed
          # compile. Escape hatch for a real sdist need: CLI flags
          # override the config (`nix shell nixpkgs#gcc -c uv pip install
          # --only-binary :none: …`).
          no-build = true;
          pip.only-binary = [":all:"];
        };
      };
    };

    # Starship toggle (the shared homeModules.starship import) lives in
    # the homeSpec namespace, outside `programs`.
    homeSpec.programs.starship.enable = true;

    # Deliberately NOT configured: no programs.git (the image bakes
    # /etc/gitconfig with the bot identity + credential helper), no
    # systemd-user units, no sops-nix, no home.sessionVariables that
    # would duplicate /etc/profile. The profile's user packages
    # (starship) reach PATH via home-path merged into the image's
    # baseTools buildEnv — see the hmAgent comment in
    # flake-parts/ociImages/code-agent.nix.
  };
}
