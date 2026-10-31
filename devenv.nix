# home's additions to the org shell (org-pkgs/devenv: fmt, check,
# sync-locks, docs, slides). Secrets for clan vars (SOPS_AGE_KEY, ...)
# come from the gitignored .env via varlock (.env.schema).
{pkgs, ...}: {
  packages = [pkgs.bun];

  scripts.clan = {
    # clan-cli at the flake's clan-core pin (flake-parts/packages.nix).
    exec = ''exec nix run "$DEVENV_ROOT#clan-cli" -- "$@"'';
    description = "clan CLI from this flake's clan-core";
  };

  enterShell = ''
    export CLAN_DIR="$DEVENV_ROOT"
    if [ -f "$DEVENV_ROOT/.env" ]; then
      eval "$(bunx varlock@1.21.1 load --format shell)"
    fi
  '';

  # Secrets load through varlock above, not devenv's dotenv.
  dotenv.disableHint = true;
}
