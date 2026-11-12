# ghost

**netsa's developer laptop**: a Dell Inspiron 7506 2-in-1 (Intel Core
i7-1165G7, 16 GiB, Intel graphics) on Wi-Fi.

| | |
| --- | --- |
| Tags | `pc` `dev` `netsa` |
| Users | netsa (full developer profile) |
| Network | Wi-Fi through NetworkManager (networking shim, `wifi` mode) |
| Config | no `configuration.nix`: everything comes from the tags, the profile and `facter.json` |

## What is loaded

- **From the tags:** KDE Plasma, the desktop apps, 1Password, the
  remote-builder client (`pc`); Docker, nix-ld and the dev apps (`dev`).
- **From the user:** netsa's full developer set: AI coding agents with
  every skill, the headroom proxy, Docker, VSCodium, Ghostty, git with a
  clan-generated signing key, the Storage Box mount.
- **Only here:** nothing; the Intel GPU, Wi-Fi and Bluetooth set
  themselves up from `facter.json`.
