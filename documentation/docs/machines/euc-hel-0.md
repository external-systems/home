# euc-hel-0

The fleet's **remote builder and CI build box**: a Hetzner Robot bare
metal server in Helsinki (Intel Xeon W-2295, 128 GiB, 2x NVMe in RAID1,
2x SATA SSD in a ZFS mirror). Formerly borg's `helsinki-manager-1`,
reinstalled into this clan.

| | |
| --- | --- |
| Tags | `server` |
| Users | root only |
| Network | public uplink, static addresses from the values flake (networking shim, `static` mode) |
| Config | `machines/euc-hel-0/configuration.nix`, `machines/euc-hel-0/disko.nix` |

## What is loaded

- **From the tag:** a headless server (`server`): no desktop or
  graphics, the common base (clan, nix daemon, OpenSSH, network tuning).
- **The remote builder** (external-systems/clanServices `remote-builder`,
  server role): every `pc` builds here (x86_64 and emulated aarch64,
  KVM for NixOS VM tests, 16 jobs). Details:
  [Remote builder (euc-hel-0)](../fleet/remote-builder.md).
- **Only here:**
    - Storage: the root on a thin LVM volume over NVMe RAID1 (array
      events to the journal), and the SATA ZFS mirror `zbulk` (monthly
      scrub, ARC capped at 16 GiB), meant for OpenEBS ZFS LocalPV.
    - A 256 MiB socket buffer ceiling (network tuning).
