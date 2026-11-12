# AGENTS.md

The external-systems home fleet: clan machines on top of the org flakes.
This repo holds machines, the clan inventory, users and home's own clan
services only. Packages, overlays, nixpkgs and dev tooling come from
external-systems/pkgs (`org-pkgs`); NixOS/home-manager modules from
external-systems/modules; agent skills from external-systems/skills
(through modules); addresses and deploy targets from the values flake
(`secrets`: the private external-systems/secrets, pinned directly; nix
needs a GitHub token to fetch it). Public repo: no secrets and no IP
literals in git.

## Layout
- `flake.nix`: inputs (all follow `org-pkgs` where they can) and the imports (`org-pkgs.flakeModules.default`: treefmt, docs and slides, lock-sync).
- `inventory.nix`: machines, tags, service instances. Deploy targets come from `secrets.hosts.<machine>.targetHost`.
- `users/<user>/default.nix`: one file per user with the NixOS account and its home-manager profile (`home-manager.users.<user>`), wired by the `users` instances in `inventory.nix`.
- `users/shared/`: home-manager modules two or more users share (one package list each), imported by those users' profiles. User preferences go here; machine traits are tags.
- `machines/<name>/`: `configuration.nix` (incl. networking, see below), `disko.nix` (install-time truth: editing it means a wipe), `facter.json` (hardware scan). `inventory.json` is clan-managed.
- `clanServices/`: `machine-type` (shared base + `pc`/`server` roles), `tags` (dev, gaming). `remote-builder` (nixbuild.net-style builds on euc-hel-0) comes from external-systems/clanServices (`clanServices` input).
- `flake-parts/` (import-tree, no import list): `clan.nix` (inventory, specialArgs incl. `secrets`), `nixpkgs.nix` (`nixosModules.nixpkgs`: org overlay), `nixosModules/networking-shim.nix`, `packages.nix` (`clan-cli` re-export), `docs.nix` (`docs.*` settings), `formatter.nix` (sizelint excludes).
- `devenv.yaml` + `devenv.lock` + `devenv.nix`: the shell (org shell from `org-pkgs/devenv`, plus `clan` and varlock-loaded `.env`).
- `documentation/`: MkDocs site (`docs/`) and reveal.js deck (`slides/slides.md`), built by `org-pkgs.flakeModules.docs`. `docs/machines/<machine>.md` says what each machine is and runs.
- `sops/`, `vars/`: clan vars. Use the `clan` CLI; never hand-edit encrypted files.

## Networking
- `hostSpec.networking.shim` (temporary, until netif in external-systems/clanServices): `wifi` mode (NetworkManager) is the default on machines whose `facter.json` has a WLAN controller; `static` mode is set per machine in `configuration.nix` from `secrets.hosts.<m>.links.<link>` and `secrets.networks.<network>`.
- Never write an address, interface or deploy target as a literal. A new machine's values go into not-secrets first (placeholders, which secrets' shape-parity check compares against), then secrets; then `nix flake update secrets` here.
- Deploy: `clan machines update <m>` from the devenv shell (it provides the GitHub token nix needs for the private `secrets` input).
- New or changed clan vars: `clan vars generate <m>` commits to the current branch, and `main` takes PRs only. Run it on a branch: `git switch main && git pull`, `git switch -c vars-<m>-<topic>`, `clan vars generate <m>`, `git push -u origin HEAD`, open a PR; deploy from `main` after it merges. `clan machines update` generates missing vars too, so run it only once the vars are on `main`.

## Tool loop
- The shell is devenv. If `DEVENV_ROOT` is unset, run commands with `devenv shell -- <cmd>`.
- `git add` new files before any `nix` command.
- `fmt`, then `check` (`nix flake check` also evaluates every machine). Both must pass before a change is done.
- After `nix flake update org-pkgs`, run `sync-locks` in the same commit.

## Tags
- A trait two or more machines share is a tag (`inventory.nix`); `configuration.nix` keeps only what that one machine has. Per-machine values for a tag are role settings (`roles.<tag>.machines.<m>.settings`).
- Hardware is not a tag: GPUs, Bluetooth and Wi-Fi set themselves up from `facter.json`. Override in `configuration.nix` only when detection is wrong.

## Rules
- Load the `nix-style` skill before editing any `.nix` file.
- One nixpkgs: never add a second nixpkgs input or `pkgs.unstable`.
- New packages go to external-systems/pkgs, new reusable modules to external-systems/modules; this repo only wires them.
- No dev-only inputs: formatting and docs come from org-pkgs (nix-style skill).
- kamrui-h1 and beelink are deployed: keep changes to their hardware, disks and users updatable in place (no wipe).
- A change to a machine's tags, users or `configuration.nix`, or a new machine, updates its page in `documentation/docs/machines/` (and the table in `index.md`) in the same PR.
- Work on a branch and open a PR. Never push to `main`.
- Never suggest running `clan vars generate` (or a `clan machines update` that would generate vars) on `main`: it commits there. Give the branch steps above.
