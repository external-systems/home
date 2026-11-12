# kamrui-h1

The **gaming and developer desktop** for **netsa and wife**: a KAMRUI
mini PC (AMD Ryzen 7 6800H, 32 GiB, Radeon graphics) on Wi-Fi. A KDE
desktop several people share, with Steam in each person's own session.

| | |
| --- | --- |
| Tags | `pc` `dev` `gaming` `netsa` `wife` |
| Users | netsa (full developer profile), wife (desktop) |
| Network | Wi-Fi through NetworkManager (networking shim, `wifi` mode) |
| Config | `machines/kamrui-h1/configuration.nix`, gaming settings in `inventory.nix` |

## What is loaded

- **From the tags:** KDE Plasma, the desktop apps, 1Password, the
  remote-builder client (`pc`); Docker, nix-ld and the dev apps (`dev`);
  jovian and Steam (`gaming`).
- **Gaming, as set for this machine** (`inventory.nix`,
  `tags.roles.gaming.machines.kamrui-h1`): no Gaming Mode entry
  (`gamingEntry = false`): everyone plays from their own KDE session.
  Per-game settings for every user: Overwatch on GE-Proton with
  `gamemoderun` and a 10 GB per-game shader cache, Risk of Rain 2 on
  GE-Proton.
- **Steam sharing** (`gaming` tag): each user has a Steam library of
  their own, here on one btrfs filesystem; `sudo steam-copy-game`
  copies a game (and its shader cache) to another user as a reflink
  copy, and shader caches are synced between users.
- **Only here:**
    - btrfs deduplication with bees on the root filesystem
      (`hostSpec.system.btrfsDedup`), so identical game data is stored
      once whoever owns it.
    - Realtek rtw89 Wi-Fi quirks (power save and PCIe ASPM off) against
      latency spikes.
    - A 128 MiB socket buffer ceiling (network tuning).
- **From the users:** netsa's full developer set (AI coding agents,
  Docker, VSCodium, Ghostty, ...); wife's desktop profile.
