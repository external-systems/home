# nixos

The **old gaming desktop** for **netsa and wife**: an MSI tower (Intel
Core i7-7700K, 32 GiB, NVIDIA Pascal GPU) on wired LAN, with an ASUS
ultrawide monitor and shared drives.

!!! note "Being retired"
    nixos will soon be retired as a desktop and turned into a server.
    Until then it is kept as it is: no new desktop or gaming work goes
    here. Moving it means swapping its `pc` and `gaming` tags for
    `server` (the `machine-type` service refuses a mix) and redoing
    `configuration.nix`.

| | |
| --- | --- |
| Tags | `pc` `dev` `gaming` `netsa` `wife` |
| Users | netsa (full developer profile), wife (desktop) |
| Network | wired, static addresses from the values flake (networking shim, `static` mode) |
| Config | `machines/nixos/configuration.nix`, `machines/nixos/disko.nix` |

## What is loaded

- **From the tags:** KDE Plasma, the desktop apps, 1Password, the
  remote-builder client (`pc`); Docker, nix-ld and the dev apps (`dev`);
  jovian and Steam with the gaming and developer boot entries, and
  Steam sharing between netsa and wife (`gaming`).
- **Only here:**
    - **NVIDIA with CUDA:** CUDA support for compute 6.1 on the CUDA 12
      package set (CUDA 13 dropped Pascal) and the `legacy_580` driver
      branch; the LTS kernel instead of jovian's Valve kernel, because
      that driver breaks most often on new kernels.
    - The one machine where home-manager evaluates its own nixpkgs
      (`useGlobalPkgs = false`), so users' packages are not rebuilt with
      CUDA.
    - **Shared drives** for netsa and wife (group `storage-users`): a
      Samsung SSD with the shared Steam library at `/mnt/sata` and a
      2 TB HDD at `/mnt/hdd`, mounted by disko, group-writable for both.
    - Flatpak, a custom SSH login message, the ultrawide display mode on
      the kernel command line.
- **From the users:** netsa's full developer set; wife's desktop
  profile.
