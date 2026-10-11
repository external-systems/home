# GitHub Self-Hosted Runners

Self-hosted GitHub Actions runners for nix CI, declared in
`flake-parts/nixosModules/github-runner.nix` and enabled per org, per host:

```nix
hostSpec.services.github-runner.org.external-systems.enable = true;
```

Currently enabled only on **kamrui-h1** for the **external-systems** org.
Org runners only — no repo-level runners: every repo in the org shares the
runner pool, and one PAT authorizes the whole fleet.

## Runner lifecycle

Runners are **ephemeral**: each job gets a fresh runner. When a job
finishes, the runner deregisters itself from GitHub, the systemd service
restarts, wipes the workdir, and registers anew. One registration per job
— nothing persists between jobs.

| | `ephemeral = true` (used) | `ephemeral = false` (static) |
|---|---|---|
| Job isolation | Complete — new registration and wiped workdir per job | Runner state, caches, and `_work` persist between jobs |
| Stale registrations | None — deregistered after every job | "Offline" ghosts accumulate after host renames/rebuilds |
| Supply-chain hygiene | A compromised/misbehaving job leaves nothing for the next | Cross-job state is a contamination vector |
| Per-job startup | A few seconds (config + registration API call) | Instant — already registered and polling |
| GitHub API churn | One registration + one deregistration per job | One registration until reconfiguration |
| PAT usage | Exchanged for a registration token at every start | Exchanged only when reconfiguring |

For a home machine that also runs desktops, games, and agent sandboxes,
per-job isolation is worth the seconds of startup.

**The PAT is never consumed.** A common misconception: ephemeral runners
do not "use up" the token in `clan vars`. The PAT stays valid for its full
GitHub-side lifetime; each runner start merely exchanges it for a
short-lived registration token. `clan vars generate` runs once per PAT, not
per job.

## Secret management

One PAT per org, provisioned by a clan vars generator
(`github-runner-<org>`):

- `share = true` — one sops-encrypted copy under
  `vars/shared/github-runner-<org>/pat/secret`, shared by any host that
  enables the org.
- `prompts.pat` — hidden, persistent prompt; answered once via
  `clan vars generate <machine>`.
- `files.pat.owner/group/mode` — deployed as
  `github-runner:github-runner 0400`.

The runner consumes the token through the canonical generator file path:

```nix
config.clan.core.vars.generators."github-runner-${name}".files.pat.path
```

which resolves to the sops-nix runtime path
(`/run/secrets/vars/shared/github-runner-<org>/pat`), or the inert
`/no-such-path` placeholder until the var is generated (eval always
succeeds; deploying without generating fails the sops manifest with a clear
error).

**No `keys` group membership is needed.** sops-nix creates every directory
in the `/run/secrets` chain `0751 root:keys` — "other" holds the traverse
bit — so file ownership (`github-runner:github-runner 0400`) alone grants
the service access. Do not add the runner user to `keys`; use generator
file perms. If a secret ever has to live at a different path, override the
path on the clan-mapped `sops.secrets` entry (the `openshell-gateway.nix`
pattern) rather than loosening groups.

**PAT requirements** (create at <https://github.com/settings/tokens>):

- fine-grained: resource owner = the org, organization permission
  **Self-hosted runners (Read and write)**, or
- classic: `admin:org` scope.

**Rotation:** `clan vars generate <machine> --generator github-runner-<org> --regenerate`, then redeploy. The next runner start picks up the new
PAT; nothing needs cleaning up on GitHub.

## Provisioning a host

```bash
clan vars generate kamrui-h1   # prompts for the PAT
nixos-rebuild --flake .#kamrui-h1 switch
```

Verify:

```bash
systemctl status github-runner-external-systems
clan vars list kamrui-h1
```

## Authoring workflows

Runners carry the default labels (`self-hosted`, `linux`, `x86_64`) plus
`<hostName>`, `<org>`, and any per-org `extraLabels`:

```yaml
jobs:
  check:
    runs-on: [self-hosted, linux, x86_64]
    steps:
      - uses: actions/checkout@v4
      - run: nix flake check
```

Pin a specific host with `runs-on: kamrui-h1`.

## Nix CI specifics

The module prepares the host for nix jobs:

- `nix.settings.trusted-users` includes `github-runner` (jobs drive the
  system nix daemon, so allowed-uris/substituter changes from workflows are
  honored).
- `nix.settings.extra-sandbox-paths = ["/dev/kvm"]` and the runner user is
  in the `kvm` group, so **NixOS VM tests** get KVM inside the build
  sandbox.
- The service PATH already ships nix, git, bash, coreutils, gnutar, and
  gzip; add more per org with
  `hostSpec.services.github-runner.extraPackages`.

Note: nix builds share the host store and binary cache regardless of
runner ephemerality — job isolation covers the runner environment, not the
nix store.

## Operations

- **Logs:** `journalctl -u github-runner-external-systems -f`
- **Parallelism:** bump `hostSpec.services.github-runner.org.<org>.count`
  (each instance is its own service and registration).
- **New org:** add the org attrset on the host, `clan vars generate`, done.
- **New host:** copy the one-line enable, `clan vars generate <host>` —
  the shared var is reused, and the runner registers as
  `<hostName>-<org>`.
