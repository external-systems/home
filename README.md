# home

[![ci](https://img.shields.io/github/actions/workflow/status/external-systems/home/ci.yml?branch=main&label=ci&logo=github)](https://github.com/external-systems/home/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/external-systems/home?label=release&color=d97757)](https://github.com/external-systems/home/releases/latest)
[![docs](https://img.shields.io/website?url=https%3A%2F%2Fhome.external.systems%2F&label=docs&up_message=online&down_message=offline)](https://home.external.systems/)
[![license](https://img.shields.io/github/license/external-systems/home)](https://github.com/external-systems/home/blob/main/LICENSE)
[![built with Nix](https://img.shields.io/badge/built_with-Nix-5277C3?logo=nixos&logoColor=white)](https://nixos.org)

The external-systems home fleet: clan machines on top of the org flakes.

| Flake | Provides |
| ----- | -------- |
| [external-systems/pkgs](https://github.com/external-systems/pkgs) | nixpkgs, flake-parts, import-tree, `overlays.default`, the dev tooling and the devenv shell |
| [external-systems/modules](https://github.com/external-systems/modules) | NixOS (`hostSpec.*`) and home-manager (`homeSpec.*`) modules, home-manager, skills |
| [external-systems/secrets](https://github.com/external-systems/secrets) (private) | fleet values: addresses, interfaces, deploy targets, the clan domain, Storage Box logins |
| [clan-core](https://git.clan.lol/clan/clan-core) | inventory, vars, deployment |

## Machines

| Machine | Role |
| ------- | ---- |
| `kamrui-h1` | AMD dev + gaming desktop (deployed) |
| `beelink` | Shared AMD desktop (deployed) |
| `nixos` | Intel desktop, NVIDIA gaming |
| `ghost` | Intel dev desktop |
| `hp-notebook` | Intel laptop |
| `euc-hel-0` | Hetzner Robot server: remote builder and CI build box ([remote-builder](https://github.com/external-systems/clanServices/tree/main/services/remote-builder)) |

## Deploy

```sh
devenv shell                     # or the auto-activation hook (devenv allow)
clan machines update kamrui-h1
clan machines install euc-hel-0 --target-host root@<rescue-ip>   # first install
```

The `secrets` input is the private external-systems/secrets, so evaluating the
machines needs a GitHub token with read access to it. The devenv shell passes
`GITHUB_TOKEN` from `.env` (or `gh auth token`) to nix as `access-tokens`.
The public `flake.lock` records only that repo's name and revision; the values
stay private in git (they still land in each machine's world-readable
`/nix/store`, so no credentials go there).

## Development

The repo follows the org flake standard: machines at the root, the formatter,
checks, docs and lock-sync from `org-pkgs.flakeModules.default` (no dev
partition, no dev-only inputs), and the devenv CLI shell. Needs Nix and devenv.

```sh
fmt              # nix fmt: treefmt with the org linters
check            # nix flake check: treefmt, lock-sync, docs, every machine
docs-build       # static docs; open result-docs/index.html from disk
```

After `nix flake update org-pkgs`, run `sync-locks` in the same commit.
