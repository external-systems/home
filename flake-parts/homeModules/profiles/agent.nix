{self, ...}: {
  # OCI-flavor agent profile: homeModules.profile-agent-base (the
  # portable agent user environment) plus the OpenShell code-agent
  # sandbox image's platform quirks. Evaluated standalone
  # (homeManagerConfiguration) at image-build time in
  # flake-parts/ociImages/code-agent.nix; the generated home-files are
  # baked into both $HOME roots (/home/agent and /sandbox) and the
  # home-path into the image toolset. Home-manager here is strictly a
  # dotfile + package-set generator: no activation, no systemd, no
  # runtime `home-manager switch` in the sandbox.
  #
  # For a NixOS/kubevirt agent sandbox, do NOT reuse this flavor —
  # compose homeModules.profile-agent-base instead (HM runs normally
  # there: systemd.user and session variables ON, identity from
  # users.users, no /etc/profile sourcing or [sandbox] marker).
  flake.homeModules.profile-agent = {lib, ...}: {
    imports = [self.homeModules.profile-agent-base];

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
    # hm-session-vars.sh for zero benefit (the old image never had
    # it). OCI-only: on NixOS flavors HM session variables are the
    # correct env channel and must NOT be force-emptied.
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
      bash.initExtra = ''
        # LOAD-BEARING: interactive ssh sessions into the sandbox are
        # `bash -i` — a NON-login shell that reads ONLY ~/.bashrc. HM's
        # own init does not source /etc/profile, so do it here: the
        # image's /etc/profile is idempotent and POSIX-safe, and it is
        # what restores PATH/wheel-deps/nix-ld/terminfo env under the
        # supervisor's scrubbed (env_clear) process env.
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

      # Starship owns the prompt: the shared settings plus sandbox
      # deltas — a literal [sandbox] marker (the machine you are typing
      # into is a disposable microVM, not the host) instead of the
      # meaningless container hostname. Glyph rendering depends on the
      # CLIENT's font (nerd fonts), same as on the NixOS hosts.
      starship.settings = {
        format = "[\\[sandbox\\]](bold purple) $all";
        hostname.disabled = true;
      };
    };
  };
}
