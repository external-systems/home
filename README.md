# home

The external-systems home fleet: clan machines on top of the org flakes.

| Flake | Provides |
| ----- | -------- |
| [external-systems/pkgs](https://github.com/external-systems/pkgs) | nixpkgs, flake-parts, import-tree, `overlays.default`, the dev tooling and the devenv shell |
| [external-systems/modules](https://github.com/external-systems/modules) | NixOS (`hostSpec.*`) and home-manager (`homeSpec.*`) modules, home-manager, skills |
| [external-systems/not-secrets](https://github.com/external-systems/not-secrets) | public placeholder values (addresses, interfaces, deploy targets); the private [secrets](https://github.com/external-systems/secrets) replaces it at deploy time |
| [clan-core](https://git.clan.lol/clan/clan-core) | inventory, vars, deployment |

## Machines

| Machine | Role |
| ------- | ---- |
| `kamrui-h1` | AMD dev + gaming desktop (deployed) |
| `beelink` | Shared AMD desktop (deployed) |
| `nixos` | Intel desktop, NVIDIA gaming |
| `ghost` | Intel dev desktop |
| `hp-notebook` | Intel laptop |
| `euc-hel-0` | Hetzner Robot server: remote builder and CI build box ([remote-builder](clanServices/remote-builder/README.md)) |

## Deploy

```sh
devenv shell                     # or the auto-activation hook (devenv allow)
clan machines update kamrui-h1 --flake . -- \
  --override-input secrets github:external-systems/secrets
```

The override swaps the public placeholders for the real values. Never commit
it (`nix flake lock --override-input`): the private URL would land in this
public `flake.lock`.

## Development

The repo follows the org flake standard: machines at the root, formatter,
checks and docs in the `dev` partition (`dev/flake.nix`, locked in
`dev/flake.lock`), and the devenv CLI shell. Needs Nix and devenv.

```sh
fmt              # nix fmt: treefmt with the org linters
check            # nix flake check: treefmt, lock-sync, docs, every machine
docs-build       # static docs; open result-docs/index.html from disk
```

After `nix flake update org-pkgs`, run `sync-locks` in the same commit.
