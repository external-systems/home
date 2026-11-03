# GitHub token rotation

Two tokens are in play, and keeping them apart is what makes rotation safe.

| Token | Where it lives | Used for |
| --- | --- | --- |
| `github-<user>` PAT | clan var, deployed to `/run/secrets/vars/shared/github-<user>/pat` | git push/pull, `gh`, the GitHub MCP server; exported as `GH_TOKEN` |
| `NIX_GITHUB_TOKEN` | `.env` in this repo (loaded by varlock), or 1Password | nix fetching the private inputs (`secrets`, `clanServices`, …) |

The devenv shell builds nix's `access-tokens` from `NIX_GITHUB_TOKEN` first,
then `GH_TOKEN`, `GITHUB_TOKEN`, and finally `gh auth token`.

## Why rotation can lock you out

`GH_TOKEN` is read from the *deployed* clan var. If you **regenerate** the PAT
on GitHub, the old one dies at once, but the machine still holds it until the
next deploy. To deploy, nix has to fetch the private `secrets` input, and it
does that with the dead token.

## The dedicated read-only token (recommended)

Create a fine-grained PAT once:

- Resource owner: `external-systems`. An org owner may need to approve it.
- Repositories: `secrets`, `clanServices`, `modules`, `pkgs`, `not-secrets`.
- Permissions: **Contents: Read-only**. Nothing else.
- A long expiry. It can only read code, so rotate it on its own schedule.

Put it in `.env` (gitignored) as `NIX_GITHUB_TOKEN=github_pat_…`, or have
varlock resolve it from 1Password. Builds then never depend on the
`github-<user>` PAT.

CI does not use this token. The org CI (`.github/workflows/ci.yml`)
mints a one-hour token from the `external-systems-nix-ci` GitHub App
(org secrets `NIX_APP_ID` and `NIX_APP_PRIVATE_KEY`, `private-repos:
secrets`), so the repository secret `NIX_GITHUB_TOKEN` is no longer needed
and can be deleted.

## Runbook: rotate `github-<user>`

1. On GitHub, **create a new** PAT. Don't regenerate the old one: keep it
   valid until step 4.
2. Store it in clan. The var is shared, so this updates it for every machine:

    ```bash
    clan vars generate <machine> --generator github-<user> --regenerate
    git add vars && git commit -m "Rotate github-<user> PAT"
    ```

3. Deploy every machine that user logs in on (`clan machines update <machine>`).
4. Delete the old PAT on GitHub.

## Recovery: the old token is already revoked

Hand nix the new token for this shell only, then deploy:

```bash
export NIX_GITHUB_TOKEN=github_pat_new…   # or: export GH_TOKEN=…
devenv shell                              # re-enter so NIX_CONFIG is rebuilt
clan machines update <machine>
```

Once the deploy is done, the clan var holds the new token and the override can
go away. With `NIX_GITHUB_TOKEN` in `.env`, this case never comes up.
