# home's additions to the org shell (org-pkgs/devenv: fmt, check,
# sync-locks, docs, slides, worktree). The clan admin key (SOPS_AGE_KEY)
# comes from 1Password through varlock (.env.schema) for the `clan`
# command only: the shell itself never holds it, and there is no .env.
{pkgs, ...}: {
  packages = [pkgs.bun];

  # `clan` with the key from 1Password (the app asks to approve the read).
  # `check` runs `clan vars check` with the real binary: it needs no key.
  scripts.clan = {
    exec = ''exec bunx varlock@1.24.0 run -- "$DEVENV_STATE/clan-cli/bin/clan" "$@"'';
    description = "The clan CLI with SOPS_AGE_KEY from 1Password (varlock run)";
  };
  org.check.extraCommands = [''"$DEVENV_STATE/clan-cli/bin/clan" vars check''];

  enterShell = ''
    export CLAN_DIR="$DEVENV_ROOT"

    # The `secrets` input is the private external-systems/secrets. nix
    # fetches github: inputs through the GitHub API, which ignores git's
    # credential helper, so hand it the token as access-tokens: GH_TOKEN
    # (the classic github-<user> PAT, exported by modules' git githubAuth
    # from the clan var), else GITHUB_TOKEN, else the gh CLI's login.
    # Skipped when none is there (a token in ~/.config/nix/nix.conf works
    # too). See docs: fleet/github-token-rotation.md.
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
    # run through the `clan` script above (not put on PATH, which would
    # shadow it); its argcomplete completions still apply to `clan`.
    # devenv modules can't read flake outputs, so build it here; the
    # out-link keeps it from being garbage-collected.
    if nix build "$DEVENV_ROOT#clan-cli" --out-link "$DEVENV_STATE/clan-cli"; then
      if [ -n "''${BASH_VERSION:-}" ] && [ -f "$DEVENV_STATE/clan-cli/share/bash-completion/completions/clan" ]; then
        # shellcheck disable=SC1091
        source "$DEVENV_STATE/clan-cli/share/bash-completion/completions/clan"
      fi
    fi

  '';

  # Secrets load through varlock (the clan script), not devenv's dotenv.
  dotenv.disableHint = true;
}
