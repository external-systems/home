_: {
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

    programs.bash = {
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

        # Unmistakable sandbox prompt (disposable microVM, not the host).
        PS1='\[\e[1;35m\][sandbox]\[\e[0m\] \[\e[1;34m\]\w\[\e[0m\]\$ '
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

    # Deliberately NOT configured: no programs.git (the image bakes
    # /etc/gitconfig with the bot identity + credential helper), no
    # systemd-user units, no sops-nix, no home.sessionVariables that
    # would duplicate /etc/profile. If user packages are ever added,
    # home-path must be merged into the image's baseTools buildEnv —
    # see the hmAgent comment in flake-parts/ociImages/code-agent.nix.
  };
}
