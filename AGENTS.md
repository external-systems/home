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
- `flake.nix`: inputs (all follow `org-pkgs` where they can) and the dev partition wiring.
- `inventory.nix`: machines, tags, service instances. Deploy targets come from `secrets.hosts.<machine>.targetHost`.
- `machines/<name>/`: `configuration.nix` (incl. networking, see below), `disko.nix` (install-time truth: editing it means a wipe), `facter.json` (hardware scan). `inventory.json` is clan-managed.
- `clanServices/`: `machine-type` (shared base + `pc`/`server` roles), `tags` (amd, intel, dev, virt). `remote-builder` (nixbuild.net-style builds on euc-hel-0) comes from external-systems/clanServices (`clanServices` input).
- `flake-parts/` (import-tree, no import list): `clan.nix` (inventory, specialArgs incl. `secrets`), `nixpkgs.nix` (`nixosModules.nixpkgs`: org overlay), `nixosModules/networking-shim.nix`, `homeModules/profiles/` (per-user profiles, wired in `users/<user>/`), `packages.nix` (`clan-cli` re-export).
- `dev/flake.nix` + `dev/flake.lock`: dev-only inputs. `dev/flake-module.nix`: formatter, checks, docs.
- `devenv.yaml` + `devenv.lock` + `devenv.nix`: the shell (org shell from `org-pkgs/devenv`, plus `clan` and varlock-loaded `.env`).
- `documentation/`: MkDocs site and reveal.js deck.
- `sops/`, `vars/`: clan vars. Use the `clan` CLI; never hand-edit encrypted files.

## Networking
- `hostSpec.networking.shim` (temporary, until netif in external-systems/clanServices) is set per machine in `configuration.nix` from `secrets.hosts.<m>.links.<link>` and `secrets.networks.<network>`. Modes: `wifi` (NetworkManager) and `static`.
- Never write an address, interface or deploy target as a literal. A new machine's values go into not-secrets first (placeholders, which secrets' shape-parity check compares against), then secrets; then `nix flake update secrets` here.
- Deploy: `clan machines update <m>` from the devenv shell (it provides the GitHub token nix needs for the private `secrets` input).

## Tool loop
- The shell is devenv. If `DEVENV_ROOT` is unset, run commands with `devenv shell -- <cmd>`.
- `git add` new files before any `nix` command.
- `fmt`, then `check` (`nix flake check` also evaluates every machine). Both must pass before a change is done.
- After `nix flake update org-pkgs`, run `sync-locks` in the same commit.

## Rules
- Load the `nix-style` skill before editing any `.nix` file.
- One nixpkgs: never add a second nixpkgs input or `pkgs.unstable`.
- New packages go to external-systems/pkgs, new reusable modules to external-systems/modules; this repo only wires them.
- Dev-only inputs go in `dev/flake.nix`, never `flake.nix`.
- kamrui-h1 and beelink are deployed: keep changes to their hardware, disks and users updatable in place (no wipe).
- Work on a branch and open a PR. Never push to `main`.
