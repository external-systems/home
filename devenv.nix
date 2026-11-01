# home's additions to the org shell (org-pkgs/devenv: fmt, check,
# sync-locks, docs, slides). Secrets for clan vars (SOPS_AGE_KEY, ...)
# come from the gitignored .env via varlock (.env.schema).
{pkgs, ...}: {
  packages = [pkgs.bun];

  enterShell = ''
    export CLAN_DIR="$DEVENV_ROOT"

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

    if [ -f "$DEVENV_ROOT/.env" ]; then
      eval "$(bunx varlock@1.21.1 load --format shell)"
    fi
  '';

  # Secrets load through varlock above, not devenv's dotenv.
  dotenv.disableHint = true;
}
