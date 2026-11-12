# beelink

A **shared developer mini PC** for **matt and netsa**: a Beelink SER
(AMD Ryzen 7 6800U, 20 GiB, Radeon graphics) on Wi-Fi.

| | |
| --- | --- |
| Tags | `pc` `dev` `netsa` `matt` |
| Users | netsa (full developer profile), matt (netsa-lite) |
| Network | Wi-Fi through NetworkManager (networking shim, `wifi` mode) |
| Config | `machines/beelink/configuration.nix` |

## What is loaded

- **From the tags:** KDE Plasma, the desktop apps, 1Password, the
  remote-builder client (`pc`); Docker, nix-ld and the dev apps (`dev`).
- **From the users:** both get AI coding agents with every skill
  (netsa: Claude Code, pi, kimi, opencode; matt: Claude Code and pi),
  the headroom proxy, Docker and Ghostty; matt also VSCodium.
- **Only here:**
    - **Odoo test instances** (`hostSpec.services.odoo`): throwaway Odoo
      databases for testing, never production, reset in seconds and
      snapshotted on demand, mail caught by Mailpit. Which instances
      exist, and whether they are on the home LAN for a Windows laptop,
      is in `configuration.nix`; how to use them is in the modules docs:
      [Odoo](https://modules.external.systems/odoo.html) and
      [reaching Odoo from other machines](https://modules.external.systems/odoo-access.html).
      Login: `admin` / `clan vars get beelink odoo-passwords/admin-password`.
    - A 128 MiB socket buffer ceiling (network tuning).
