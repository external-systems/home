# hp-notebook

**wife's laptop**: an HP Laptop 14 (Intel Celeron N4120, 4 GiB, Intel
graphics) on Wi-Fi. A plain desktop, kept light for the small CPU and
memory.

| | |
| --- | --- |
| Tags | `pc` `wife` |
| Users | wife (desktop) |
| Network | Wi-Fi through NetworkManager (networking shim, `wifi` mode) |
| Config | no `configuration.nix`: everything comes from the tags, the profile and `facter.json` |

## What is loaded

- **From the tags:** KDE Plasma, the desktop apps, 1Password, the
  remote-builder client (`pc`). No `dev` or `gaming`: no Docker, dev
  apps or Steam.
- **From the user:** wife's desktop profile: Firefox, media apps,
  Plasma settings.
- **Only here:** nothing. Builds run on euc-hel-0, so updates do not
  compile on the laptop.
