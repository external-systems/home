# Machines and networking

## Values, not literals

No address, interface name or deploy target is written in this repo. They come
from the values flake, input `secrets`:

the private external-systems/secrets, pinned directly in `flake.nix`
(clan can't pass `--override-input`). Evaluating the machines needs a
GitHub token with read access to it; the devenv shell hands nix
`GITHUB_TOKEN` from `.env` (or `gh auth token`) as `access-tokens`:

```sh
clan machines update kamrui-h1
```

The public [external-systems/not-secrets](https://github.com/external-systems/not-secrets)
holds the same shape with placeholder values; secrets checks itself
against it.

Machine modules get the tree as the `secrets` module argument
(`clan.specialArgs`, `flake-parts/clan.nix`); the inventory reads deploy
targets from `secrets.hosts.<machine>.targetHost`.

## The networking shim

Until the IfState-based `netif` clan service in external-systems/clanServices
is ready, each machine configures its own networking in `configuration.nix`
through `hostSpec.networking.shim` (`flake-parts/nixosModules/networking-shim.nix`):

| Mode | What it does | Machines |
| ---- | ------------ | -------- |
| `wifi` | NetworkManager with DHCP/RA, WiFi power-save off, BBR + `fq`, rtw89 PM quirks | kamrui-h1, beelink, ghost, hp-notebook |
| `static` | Fixed addresses and default routes on one interface, from `secrets.hosts.<m>.links.<link>` and `secrets.networks.<network>` | nixos, euc-hel-0 |

The option names mirror the values schema, so moving a machine to netif is a
rewrite of that one attrset.
