---
name: determinate
description: "Determinate Systems + FlakeHub: where the docs live (docs.determinate.systems), publishing, FlakeHub Cache/private flakes/resolved store paths, semver (tagged vs rolling 0.1.COMMITS_ON_BRANCH), and the fh CLI incl. fh apply deployment. Load when touching flake input URLs, releases, or machine deploys."
---

# Determinate Systems and FlakeHub

Determinate Nix, FlakeHub, and the `fh` CLI: where the docs live, how
publishing and versioning work, and how machines deploy. The user runs
Determinate Nix everywhere (workstations, CI runners, machines), publishes
flakes to [FlakeHub](https://flakehub.com), and deploys pull-based with
`fh apply`. Assume Determinate Nix on every host: never emit
`experimental-features` boilerplate, install-script workarounds, channel
setup, or `nix-env` advice.

## Where the docs are

All docs live at [docs.determinate.systems](https://docs.determinate.systems):

| Topic | URL |
|---|---|
| Docs home / map | https://docs.determinate.systems |
| Determinate Nix (the Nix distribution) | https://docs.determinate.systems/determinate-nix/ |
| Determinate Nix best practices | https://docs.determinate.systems/determinate-nix/best-practices/ |
| FlakeHub overview | https://docs.determinate.systems/flakehub/ |
| Publishing flakes | https://docs.determinate.systems/flakehub/publishing/ |
| FlakeHub Cache | https://docs.determinate.systems/flakehub/cache/ |
| Private flakes | https://docs.determinate.systems/flakehub/private-flakes/ |
| Resolved store paths | https://docs.determinate.systems/flakehub/store-paths/ |
| SemVer concepts | https://docs.determinate.systems/flakehub/concepts/semver/ |
| FlakeHub URLs | https://docs.determinate.systems/flakehub/concepts/urls/ |
| `fh` CLI | https://docs.determinate.systems/flakehub/cli/ |
| Nixpkgs versions | https://docs.determinate.systems/flakehub/concepts/semver/ (Nixpkgs section) |

What FlakeHub adds over plain git flakes: semantic versioning for flake
releases, private flakes, FlakeHub Cache (repository-level access
control, OIDC/no-token auth), and resolved store paths persisted per
release (no re-evaluation on the deploy target).

## How FlakeHub works

- **Publishing** is on-demand (CI or `fh`/flakehub-push), not per push.
  A release pins the flake content behind a SemVer version and, with
  `include-output-paths: true`, persists the resolved store paths.
- **URLs** take the form `https://flakehub.com/f/<org>/<repo>/<version-req>`
  and can be used directly as flake input URLs — no registry indirection.
- **FlakeHub Cache** serves the built closures of published flakes;
  access control is at the git-repository level and authenticates via
  OIDC (CI) or `fh login` (interactive) — no substituter keys to juggle
  (`determinate-nix-action` + `flakehub-cache-action` are the CI wired
  pair).
- **Private flakes** resolve for authenticated users/org members only.

## Semantic versioning for flakes

FlakeHub enables a SemVer subset on flake releases: `major.minor.patch`
with `=` (exact) and `*` (wildcard) version requests. Two release
models:

**Tagged** releases — for projects with a defined SemVer cadence. The
author picks versions; tags map to releases (`=0.1.26`).

**Rolling** releases — for continuously updated flakes. The scheme:

```
0.1.<patch>   where <patch> = number of commits on the branch
```

- SemVer major is always **0**, minor is **1**, and the patch is the
  *count of commits on that branch* at publish time — i.e. commits since
  git init on that branch, not since the last release.
- Every new publish lands a higher `0.1.<n>`; `0.1.*` or plain `0.1` in
  an input URL tracks the newest.
- Example: `https://flakehub.com/f/helix-editor/helix/0.1.6953`
  corresponds to revision
  `d79cce4e4bfc24dd204f1b294c899ed73f7e9453` (the URL renders the
  resolved rev as `0.1.6953+rev-<rev>`).

Nixpkgs on FlakeHub follows its own conventional scheme:

| Constraint | Meaning |
|---|---|
| `0` / `*` | most recently published **stable** nixpkgs |
| `0.{YYMM}` | latest release train of that branch (e.g. `0.2505` → `nixos-25.05`) |
| `0.1` | most recently published **unstable** nixpkgs |
| `0.1.{commit}` | latest unstable release at *at least* the Nth commit of the epoch |
| `=0.1.N` | exactly the Nth-commit release |

`DeterminateSystems/nixpkgs-weekly` mirrors unstable with weekly
publishes — useful where several refreshes a day is too much churn.

Version range queries work with the `fh` CLI:

```
fh list versions --json NixOS/nixpkgs "0" | jq -r ".[-5:] | .[].version"
fh list versions --json NixOS/nixpkgs "0.1" | jq -r ".[-5:] | .[].version"
```

## The `fh` CLI

| Command | What it does |
|---|---|
| `fh login` / `fh status` | authenticate to FlakeHub (device flow), show status |
| `fh add <flake>` | add the flake as an input to the local `flake.nix` (writes a pinned version URL) |
| `fh init` | scaffold a new `flake.nix` interactively |
| `fh convert` / `fh eject` | rewrite inputs from GitHub URLs to FlakeHub URLs (or back) |
| `fh search <q>` / `fh list flakes\|orgs\|releases\|versions` | discovery |
| `fh resolve <ref>#<output>` | print the resolved store path of a published output (needs `include-output-paths` at publish) |
| `fh fetch <ref>#<output> <link>` | fetch a closure directly from FlakeHub Cache into the store and link it |
| `fh apply <system> <ref>` | apply a published NixOS / home-manager / nix-darwin configuration to the current host |

## How `fh apply` works

`fh apply` deploys a **published** configuration. It does not evaluate
Nix on the target: it resolves the flake reference to the persisted
store path (from the release's resolved store paths), pulls the closure
from FlakeHub Cache, builds/links the activation artifact, and runs it.

Per system:

| System command | Default output | Action |
|---|---|---|
| `sudo fh apply nixos "<ref>"` | `nixosConfigurations.$(hostname)` | runs `switch-to-configuration switch` (or `boot`/`test`/`dry-activate`) |
| `fh apply home-manager "<ref>"` | `homeConfigurations.$(whoami)` | runs the HM activate script |
| `sudo fh apply nix-darwin "<ref>"` | `darwinConfigurations.<localhostname>` | runs `darwin-rebuild activate` |

The `<ref>` is `org/repo/<version-req>#<output>`; on the home repo:

```
fh apply nixos "andrewthomaslee/home/0.1#nixosConfigurations.kamrui-h1"  # or just:
fh apply nixos "andrewthomaslee/home/0.1"          # defaults to $(hostname)
fh apply nixos "andrewthomaslee/home/0.1" boot     # switch to new gen at next boot
```

Deployment style of the home repo's fleet: **pull-based** — CI publishes
a release to FlakeHub, machines run the `apply-*` packages (e.g.
`apply-now home`, `apply-and-reboot home` for a clean remote reboot).
`fh apply` requires a FlakeHub plan with cache access; private flakes
additionally need `fh login` on the target machine. Wrapping a custom
default output with a URL path is possible with the full
`https://flakehub.com/f/:org/:project/:version-req#:output` form —
`fh apply` accepts it verbatim.

Where this fits in CI: the `flake-parts` skill (`checks` gate) and
workflow files `release.yml`/`machines.yml` handle building + publishing;
this skill covers what machines do with the result.
