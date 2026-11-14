# GitHub token rotation

One token per user covers everything: a **classic** PAT stored as the
`github-<user>` clan var.

| Token | Where it lives | Used for |
| --- | --- | --- |
| `github-<user>` PAT | clan var, deployed to `/run/secrets/vars/shared/github-<user>/pat` | git push/pull, `gh`, the GitHub MCP server, and nix fetching the private inputs (`secrets`, `clanServices`, …); exported as `GH_TOKEN` |

It has to be classic. A fine-grained PAT has a single resource owner, either
your account or one org, so one can't reach both personal repos and
external-systems. Scopes: `repo`, `workflow` (pushes that touch
`.github/workflows/`) and `read:org`.

The devenv shell builds nix's `access-tokens` from `GH_TOKEN`, then
`GITHUB_TOKEN`, and finally `gh auth token`.

CI does not use this token. The org CI (`.github/workflows/ci.yml`)
mints a one-hour token from the `external-systems-nix-ci` GitHub App
(org secrets `NIX_APP_ID` and `NIX_APP_PRIVATE_KEY`, `private-repos:
secrets`).

## Why rotation can lock you out

`GH_TOKEN` is read from the *deployed* clan var. If you **regenerate** the PAT
on GitHub, the old one dies at once, but the machine still holds it until the
next deploy. To deploy, nix has to fetch the private `secrets` input, and it
does that with the dead token. Create a new token instead and keep the old one
valid until every machine is deployed.

## Runbook: rotate `github-<user>`

1. On GitHub, **create a new** classic PAT (Settings → Developer settings →
   Tokens (classic)) with `repo`, `workflow` and `read:org`. Don't regenerate
   the old one: keep it valid until step 4.
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
export GH_TOKEN=ghp_new…   # this shell only
devenv shell               # re-enter so NIX_CONFIG is rebuilt
clan machines update <machine>
```

Once the deploy is done, the clan var holds the new token and the override can
go away.
