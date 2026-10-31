# Machines and networking

## Values, not literals

No address, interface name or deploy target is written in this repo. They come
from the values flake, input `secrets`:

- publicly it is [external-systems/not-secrets](https://github.com/external-systems/not-secrets)
  (documentation-range placeholders), so `nix flake show` and
  `nix flake check` always evaluate;
- deploys swap in the private [external-systems/secrets](https://github.com/external-systems/secrets),
  never committing the override:

```sh
clan machines update kamrui-h1 --flake . -- --override-input secrets github:external-systems/secrets
```

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
