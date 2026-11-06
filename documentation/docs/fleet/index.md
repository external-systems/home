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
is ready, networking goes through `hostSpec.networking.shim`
(`flake-parts/nixosModules/networking-shim.nix`):

| Mode | What it does | Set by | Machines |
| ---- | ------------ | ------ | -------- |
| `wifi` | NetworkManager with DHCP/RA | the default when `facter.json` has a WLAN controller | kamrui-h1, beelink, ghost, hp-notebook |
| `static` | Fixed addresses and default routes on one interface, from `secrets.hosts.<m>.links.<link>` and `secrets.networks.<network>` | the machine's `configuration.nix` | nixos, euc-hel-0 |

The option names mirror the values schema, so moving a machine to netif is a
rewrite of that one attrset.

## Network tuning

Performance tuning is separate from the shim: every machine gets
`hostSpec.networking.optimization` from external-systems/modules, enabled by
the machine-type service. It sets BBR + `fq`, socket buffer ceilings,
`tcp_notsent_lowat`, TCP Fast Open, irqbalance and Wi-Fi power-save off, all
as `mkDefault`. The buffer ceiling (`optimization.bufferMax`) is 32 MiB by
default, 128 MiB on kamrui-h1 and beelink, and 256 MiB on euc-hel-0. kamrui-h1 also sets
the rtw89 power-management quirks in its own `configuration.nix`.

## Tags and per-machine config

A trait two or more machines share is a tag in `inventory.nix`; only what
one machine has stays in its `configuration.nix` (disks, addresses, the
NVIDIA driver branch, monitors, shared drives). The tags come in three
kinds:

| Kind | Tags | Service |
| ---- | ---- | ------- |
| Machine type | `pc`, `server` (one per machine; a server with `pc` or `gaming` fails to evaluate) | `machine-type` |
| Purpose | `dev`, `gaming` | `tags` |
| Users | `netsa`, `wife`, `matt` | `users` instances |

A tag that needs a per-machine value takes it as a role setting, for
example `gaming.machines.<m>.settings.user` (the Steam Gaming Mode user;
unset boots the gaming entry to the KDE login screen) in the `tags` instance.

Hardware is not a tag. It comes from each machine's `facter.json`:

- The AMD, Intel and NVIDIA GPU modules and Bluetooth from
  external-systems/modules set themselves up (for NVIDIA, including the
  kernel module and driver branch the card needs).
- The networking shim defaults to Wi-Fi on machines with a WLAN controller.
- nixos-facter handles microcode, firmware and the KVM modules; nested KVM
  is the kernel default.
