---
name: github-actions
description: "Creating GitHub Actions workflows for repos in the external-systems org that run on its self-hosted NixOS runners (currently kamrui-h1): runner labels and targeting, what is preinstalled on the runner, the org-wide reusable workflows in external-systems/actions (nix flake check, check-gated rolling-semver tag, nix build, NixOS machine build, NixOS VM test — call with `uses: ...@v1`), local nix flake check / nix build / VM test patterns with readable logs, the 0.<rolling-minor>.<commit-count> release tagging convention, and reading failed run logs with gh. Load when writing, editing, or debugging GitHub Actions CI for any external-systems repo."
---

# github-actions — external-systems self-hosted runners

How to write GitHub Actions for repos owned by the **external-systems**
org. All CI runs on self-hosted NixOS runners — **not** GitHub-hosted
`ubuntu-latest`. The defining consequence: **nix, KVM, and the CI
toolset are already on the host** — never install nix, never use
Determinate Systems actions, never use setup actions for tooling the
host already has.

Ready-to-copy workflow templates live in `references/` next to this
file — copy the one closest to the task and adjust.

## Org-wide reusable workflows — external-systems/actions (start here)

The four standard org jobs live as **reusable workflows** (`on:
workflow_call`) in the [actions](https://github.com/external-systems/actions)
repo — a library repo that never runs itself (no push/PR/dispatch
triggers, no secrets). Call one from any org repo with `uses:`; the
called workflow runs in the CALLER's context (caller's checkout,
`GITHUB_TOKEN` and secrets — the actions repo is just the recipe):

| File | What it does | Key inputs |
| --- | --- | --- |
| `nix-flake-check.yml@v1` | `nix flake check --show-trace -L` | `runs-on`, `flake-check-flags` |
| `nix-flake-check-and-tag.yml@v1` | flake check **gates** a `0.<minor>.<commit-count>` tag push (idempotent, serialized) | `rolling-minor` (required), `runs-on` |
| `nix-build.yml@v1` | `nix build <installable> -L` | `installable` (required), `build-flags`, `runs-on` |
| `nixos-machine-build.yml@v1` | builds `.#nixosConfigurations.<host>...toplevel` — nests a call to `nix-build.yml` | `host` (required), `runs-on` |
| `nixos-vm-test.yml@v1` | `nix run .#vm-test -- <test>-<size>` | `test` (required), `size` (sm/md/lg), `extra-args`, `runs-on` |

```yaml
jobs:
  check-and-tag:                      # home/release.yml's push path, verbatim
    uses: external-systems/actions/.github/workflows/nix-flake-check-and-tag.yml@v1
    with:
      rolling-minor: "3"
```

Rules for consuming them:

- **Pin `@v1` (or a full SHA), never `@main`.** The actions repo is the
  org's CI root of trust; the tag is the reviewed artifact.
- The repo's Actions policy must allow references from
  `external-systems/*` (relevant once allowed-actions is tightened from
  "all").
- **The fork guard is baked into every reusable job**
  (`github.event.pull_request.head.repo.full_name == github.repository`)
  — fork PR code can never reach a self-hosted runner. Do not re-add a
  guard, and do not remove it in the actions repo.
- **Jobs using `uses:` cannot have a `strategy.matrix`.** For a
  fixed set, write one small calling job per item (home's builds.yml:
  five `nixos-machine-build` calls). For a DYNAMIC matrix (home's
  vm-tests.yml discovers tests from the tree at runtime), the workflow
  stays local — copy the step patterns below, the reusable workflows
  can't help there.
- `nixos-machine-build.yml` nests a call to `nix-build.yml` — two
  levels of `uses:`; GitHub allows three.
- Caller `permissions:` must cover what the reusable job declares
  (`contents: write` for the tag job) — permissions never elevate
  beyond the caller.

Everything below about runner targeting, preinstalled tooling and log
reading applies inside the reusable workflows too — they run on the
same runners with the same toolset.

## The runners

- Org-level runners registered against `https://github.com/external-systems`,
  managed by the NixOS module
  `flake-parts/nixosModules/github-runner.nix` in the
  [home](https://github.com/external-systems/home) flake.
- Currently deployed: **kamrui-h1** (AMD desktop, x86_64-linux, KVM).
  `github-runner.org.external-systems.enable = true` in
  `machines/kamrui-h1/configuration.nix`.
- **Ephemeral**: one registration per job, workdir wiped between jobs.
  Never rely on state from a previous job; never store anything outside
  `$GITHUB_WORKSPACE` you expect to keep. (The nix store and the daemon
  cache DO persist across jobs — repeat builds are warm and fast.)
- The runner user is a **nix trusted user** in the **kvm** group, with
  `/dev/kvm` passed into the nix build sandbox and
  `accept-flake-config = true`: a repo flake's own `nixConfig`
  `extra-substituters`/`extra-trusted-public-keys` are honored
  automatically, so jobs use whatever binary caches the flake declares.

### Targeting

Every runner carries GitHub's default labels (`self-hosted`, `linux`,
`x64`) plus `<hostName>`, `<system>`, `<org>`:

```yaml
runs-on: [self-hosted, external-systems]   # any org runner (preferred)
runs-on: kamrui-h1                          # pin a specific host (single label)
runs-on: [self-hosted, x86_64-linux]        # any x86_64-linux org runner
```

If a job silently hangs in "queued" forever, the label combination
matched no registered runner — check the repo/org's Actions → Runners
page and the service on the host (`systemctl status github-runner-*`).

### Preinstalled on every runner's PATH

From the nixpkgs `services.github-runners` module: **nix** (flakes +
nix-command enabled, system daemon), **git**, coreutils, gnutar, gzip,
bash. From the home module's `extraPackages` default: **gh**, **jq**,
**yq** (yq-go), **curl**, **wget**, **openssh**, **git-lfs**.

Everything else comes from the repo's flake (`nix develop`,
`nix build .#...`, `nix run .#...`) — that is the point of nix CI:
the workflow file stays tiny and the toolchain is pinned by flake.lock.

`gh` on the runner is authenticated by `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`
when a step sets it (needed for `gh release create`, `gh run view`).

## The three core job patterns

All three share one rule: **always pass `-L` (and `--show-trace` for
flake check)** so full build logs stream into the job log. The job log
is the artifact — a red job must be debuggable from the log alone.

### Trigger policy (org rule — applies to every repo)

- **On every push/PR: `nix flake check` only.** Nothing else runs
  automatically.
- **Builds and VM tests are `workflow_dispatch` only** — triggered by a
  human/agent from the Actions tab or `gh workflow run <file>`.
- **VM tests NEVER run automatically**, under any trigger.
- **Every push to main is auto-tagged** `0.<rolling-minor>.<commit-count>`
  after the flake check passes (see Releases). Creating the GitHub
  *release* for a tag is manual.

### 1. nix flake check

```yaml
- uses: actions/checkout@v6.0.2
- run: nix flake check --show-trace -L
```

### 2. nix build

```yaml
- run: nix build .#<attr> --show-trace -L
```

For machine toplevels in a dendritic repo, matrix over
`.#nixosConfigurations.<name>.config.system.build.toplevel`.

### 3. NixOS VM tests

KVM is available — tests run at full speed, never TCG. **Manual
dispatch only, always.** And they run on a desktop that is in use, so
there is a hard resource rule, enforced in the home flake by
`checks.vm-test-resources` (runs inside `nix flake check`, so it gates
every push):

- `virtualisation.memorySize` ≤ **16384 MiB** per VM
- `virtualisation.cores` ≤ **8** per VM
- Undeclared = nixosTest defaults (1024 MiB, 1 core) — always safe.
- Multi-node: keep nodes × memorySize well under the host's RAM
  (kamrui-h1 has **30 GiB**, Ryzen 7 6800H **8c/16t** — measured from
  its facter.json; re-check if the runner fleet changes).

Copy this gate into any other repo that adds VM tests (it is a small
grep-based runCommand in `flake-parts/checks.nix` of the home flake).

Two shapes:

- **Repo exposes tests as checks/derivations**:
  `nix build .#checks.x86_64-linux.<test> -L`. The nixos-test driver
  runs inside the build sandbox; the build log (streamed by `-L`) is
  the complete driver log with every VM's console output.
- **The home flake's `vm-test` app** (`legacyPackages.vmTests`, sm/md/lg
  variants): `nix run .#vm-test -- <name>-sm` — sandboxed, exit code =
  result, watchdog-bounded; the job log is the test log. Discover the
  matrix dynamically so the workflow never hardcodes test names:

  ```yaml
  - id: list
    run: |
      tests=$(nix eval --json .#legacyPackages.x86_64-linux.vmTests \
        --apply 'builtins.attrNames' | jq -c 'map(select(endswith("-sm"))) | sort')
      echo "tests=$tests" >> "$GITHUB_OUTPUT"
  # matrix: test: ${{ fromJSON(needs.list.outputs.tests) }}
  ```

Reproducibility is structural: the test closure comes from flake.lock,
the runner is ephemeral, and the nix store is content-addressed. The
only host inputs are KVM and the (trusted) daemon. Do not add
`--impure`, `--no-sandbox`, or network fetches to test jobs.

Give VM-test jobs a generous `timeout-minutes` (60–90); the app's own
watchdog fires first on a hang.

## Releases: FlakeHub-style rolling semver

Convention: **`0.<rolling-minor>.<commit-count-since-init>`** (home is
on `0.3.x`). Split behavior:

- **Tagging is automatic and gated**: every push to `main` runs
  `nix flake check` first; only a green push gets tagged
  `0.<minor>.$(git rev-list --count HEAD)`. In repos that use the org's
  reusable set this is one call to `nix-flake-check-and-tag.yml@v1`
  (the gate ships with the template — callers can't forget it). The
  tag push does not retrigger workflows (they filter
  `branches: [main]`, and `GITHUB_TOKEN` pushes don't trigger events
  anyway).
- **The GitHub release is manual**: `workflow_dispatch` with an optional
  `tag` input (default: latest `0.<minor>.*`), gated behind a pre-flight
  `nix flake check` so a red tree is never released. The release job
  stays repo-local (gh release, --latest semantics) — it is NOT part of
  the reusable set.

Tag job essentials (as implemented in the actions repo's
`nix-flake-check-and-tag.yml@v1` — call it, don't copy it; this is for
understanding and for repos that hand-roll tagging):

```yaml
- uses: actions/checkout@v6.0.2
  with:
    fetch-depth: 0            # REQUIRED — the patch number is git history depth
- run: |
    TAG="0.${ROLLING_MINOR}.$(git rev-list --count HEAD)"
    git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && exit 0  # idempotent
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git tag -a "$TAG" -m "Release $TAG" "${{ github.sha }}" && git push origin "$TAG"
```

Release step uses the preinstalled `gh` (`gh release create "$TAG"
--generate-notes --latest`), `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`,
`permissions: contents: write`.

## Reading failed runs (humans and agents)

The runner needs no extra tooling for log access — use `gh` from any
machine with repo access:

```bash
gh run list --repo external-systems/<repo> --limit 10
gh run view <run-id> --repo external-systems/<repo>            # job summary
gh run view <run-id> --repo external-systems/<repo> --log-failed  # failing steps' logs
gh run watch <run-id> --repo external-systems/<repo>           # live-follow a run
gh run rerun <run-id> --failed --repo external-systems/<repo>  # retry red jobs
```

Because every nix step runs with `-L`, `--log-failed` output contains
the actual nix build error / VM driver failure — no artifact download
needed. VM-test post-mortem beyond the log (screenshots, junit.xml,
resumable VM state) is a *local* driver-mode run
(`nix run .#vm-test -- <name>-sm --driver`), not a CI artifact.

## House rules for workflows in this org

- **Trigger policy** (repeated because it's the org's core rule):
  `nix flake check` is the ONLY automatic job (push + PR). Builds and
  VM tests are `workflow_dispatch` only. VM tests never run
  automatically, ever. Pushes to `main` are auto-tagged with the rolling
  semver AFTER the flake check passes; publishing the GitHub release is
  manual.
- **Prefer the org's reusable workflows**
  (`external-systems/actions`, `@v1`) for the four standard jobs — flake
  check, check-gated tag, nix build/machine build, single VM test.
  Write repo-local steps only for repo-specific jobs (dynamic matrix,
  release publishing, anything with custom logic).
- Self-hosted only: `runs-on` must resolve to org runners (see
  Targeting). Never `ubuntu-latest`.
- Never install nix or use `DeterminateSystems/*` actions — nix is the
  host OS package manager and is already configured (substituters,
  trusted user, KVM).
- `actions/checkout` is the only marketplace action needed in most
  repos; use `gh` (preinstalled) instead of release/upload actions.
- `concurrency: { group: ${{ github.workflow }}-${{ github.ref }},
  cancel-in-progress: true }` on push workflows — runners are few, don't
  queue stale jobs. Manual/heavy workflows use the workflow name as the
  group with `cancel-in-progress: false` (never cancel a build or VM
  test mid-flight; queue it).
- Keep workflows thin: anything non-trivial belongs in the flake
  (a package, an app, a check), invoked as one `nix` line. The workflow
  is plumbing, not logic.
- Ephemeral runners wipe the workdir: everything a job needs comes from
  the checkout + nix; secrets come from `secrets.*`/`GITHUB_TOKEN`, never
  from files left on the host.

## Enabling a runner on a new host (home flake only)

```nix
# machines/<host>/configuration.nix
hostSpec.services.github-runner.org.external-systems.enable = true;
# count: hostSpec.services.github-runner.org.external-systems.count = 2;
```

Then a human runs `clan vars generate kamrui-h1` (once per org PAT —
fine-grained PAT with org "Self-hosted runners" R/W, or classic
`admin:org`) and redeploys. Agents never run clan vars generation or
deploys; report the commands for the human.
