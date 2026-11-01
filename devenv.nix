# home's additions to the org shell (org-pkgs/devenv: fmt, check,
# sync-locks, docs, slides). Secrets for clan vars (SOPS_AGE_KEY, ...)
# come from the gitignored .env via varlock (.env.schema).
{pkgs, ...}: {
  packages = [pkgs.bun];

  enterShell = ''
    export CLAN_DIR="$DEVENV_ROOT"

    if [ -f "$DEVENV_ROOT/.env" ]; then
      eval "$(bunx varlock@1.21.1 load --format shell)"
    fi

    # The `secrets` input is the private external-systems/secrets. nix
    # fetches github: inputs through the GitHub API, which ignores git's
    # credential helper, so hand it the token as access-tokens: GH_TOKEN
    # (exported by modules' git githubAuth from the github-<user> clan
    # var), else GITHUB_TOKEN, else the gh CLI's login. Skipped when none
    # is there (a token in ~/.config/nix/nix.conf works too).
    gh_token="''${GH_TOKEN:-''${GITHUB_TOKEN:-}}"
    if [ -z "$gh_token" ] && command -v gh >/dev/null; then
      gh_token="$(gh auth token 2>/dev/null || true)"
    fi
    if [ -n "$gh_token" ]; then
      NIX_CONFIG="$(printf '%s\n%s' "''${NIX_CONFIG:-}" "access-tokens = github.com=$gh_token")"
      export NIX_CONFIG
    fi
    unset gh_token

    # clan-cli at the flake's clan-core pin (flake-parts/packages.nix),
    # put on PATH as the real binary so its argcomplete completions work.
    # devenv modules can't read flake outputs, so build it here; the
    # out-link keeps it from being garbage-collected.
    if nix build "$DEVENV_ROOT#clan-cli" --out-link "$DEVENV_STATE/clan-cli"; then
      export PATH="$DEVENV_STATE/clan-cli/bin:$PATH"
      if [ -n "''${BASH_VERSION:-}" ] && [ -f "$DEVENV_STATE/clan-cli/share/bash-completion/completions/clan" ]; then
        # shellcheck disable=SC1091
        source "$DEVENV_STATE/clan-cli/share/bash-completion/completions/clan"
      fi
    fi

  '';

  # Secrets load through varlock above, not devenv's dotenv.
  dotenv.disableHint = true;
}
