---
name: disko
description: "Disko declarative disk partitioning: the disko.devices tree, CLI modes (destroy/format/mount) vs the NixOS module's auto-injected fileSystems/boot/swapDevices, how clan-core auto-imports machines/NAME/disko.nix and carries the disko module, filesystem recipes (ext4, btrfs subvolumes, zfs pools/mirror), LUKS + clan vars neededFor=\\\"partitioning\\\" key patterns (incl. initrd SSH unlock), and 2-disk RAID1/ZFS-mirror redundancy for critical machines. Load when writing or editing machines/HOST/disko.nix or working on encrypted/redundant disk layouts."
---

# disko

[disko](https://github.com/nix-community/disko) is nix-community's
declarative disk-partitioning tool. One Nix expression (`disko.devices`)
describes disks, partitions, RAID arrays, LUKS containers and
filesystems; from it disko either (a) partitions/formats/mounts the real
disks via a CLI, or (b) — as a NixOS module — generates the
`fileSystems`, `swapDevices` and `boot` config the system needs to boot
that layout. Load this skill when writing or editing
`machines/<host>/disko.nix`, adding a machine, or building an encrypted
or redundant (2-disk) layout.

In this flake every machine already has a `machines/<name>/disko.nix`;
it is clan-auto-imported (see below) and was generated at install time.
Treat it like `facter.json`: **changing it requires wiping and
reinstalling the machine** (normal rebuilds never reformat — see
[Rebuild vs format](#rebuild-vs-format)).

## Where the docs are

| Topic | URL |
|---|---|
| README + docs index | https://github.com/nix-community/disko |
| Quickstart (manual install) | https://github.com/nix-community/disko/blob/master/docs/quickstart.md |
| CLI reference (`--mode`, flags) | https://github.com/nix-community/disko/blob/master/docs/reference.md |
| Example layouts (also used as tests) | https://github.com/nix-community/disko/tree/master/example |
| Real-world templates (`nix flake init`) | https://github.com/nix-community/disko-templates |
| Type sources (recursive options) | https://github.com/nix-community/disko/tree/master/lib/types |
| Disk images w/ secrets | https://github.com/nix-community/disko/blob/master/docs/disko-images.md |
| clan disk-encryption guide (vars + ZFS + initrd SSH) | https://clan.lol/docs/26.05/guides/disk-encryption |
| clan vars guide | https://clan.lol/docs/26.05/guides/vars/intro-to-vars |

There is no rendered option reference: disko's options are recursive
generated types, so `lib/types/*.nix` + the `example/` directory are the
authoritative docs.

## The mental model

One spec, two consumers:

1. **The disko CLI** — a one-shot, destructive partitioning tool. Run it
   explicitly (typically during install, or via nixos-anywhere / clan).
   Modes (`--mode`): `destroy` (wipe tables), `format` (create
   partitions/zpools/RAIDs/filesystems that don't exist yet), `mount`
   (mount under `--root-mountpoint`, default `/mnt`), and the combined
   `destroy,format,mount` (legacy name: `--mode disko`). `format` alone
   is the "formatting-only" pass — see the nixos machine below. DANGER
   flags: `--yes-wipe-all-disks` skips the safety check (automation
   only); `--dry-run` prints the script instead of running it.
2. **The NixOS module** — evaluated on every rebuild. It merges the
   generated config into the machine (gated by `disko.enableConfig`,
   default `true`): `fileSystems` (from mountpoints, using
   `/dev/disk/by-partlabel/disk-<disk>-<part>` or fs-uuid devices),
   `swapDevices`, `boot.loader.grub.devices` (from `EF02` BIOS-boot
   partitions), `boot.initrd` bits (luks devices, zfs support), and
   exposes `system.build.diskoScript` / `diskoScriptNoDeps` /
   `diskoImagesScript` / `installTest` / `vmWithDisko` outputs.

Spec shape — `disko.devices` is a tree of typed nodes (`disk` → `gpt` →
`partitions` → content, which recurses: luks → btrfs, mdraid → gpt, ...):

```nix
disko.devices = {
  disk = {
    <name> = {
      type = "disk";
      device = "/dev/disk/by-id/<stable-id>";   # never /dev/nvme0n1
      content = { type = "gpt"; partitions = { ... }; };
    };
  };
  mdadm.<array> = { type = "mdadm"; level = 1; content = ...; };
  zpool.<pool>  = { type = "zpool"; mode = "mirror"; datasets = ...; };
};
```

Partition types: `EF00` (ESP), `EF02` (BIOS boot/grub), sizes like
`"500M"`, `"100%"`, `"1G"`; `priority` orders partitions below `100%`.
Always address disks by `/dev/disk/by-id/...` so device ordering can
never shuffle between boots or machines.

## How clan-core wires it (this repo)

Two pieces of magic, both verified in clan-core source:

**1. Auto-import of `disko.nix`.** clan's machine module
(`nixosModules/machineModules/forName.nix`) imports, for every machine
with `machineClass = "nixos"`:

```nix
imports = builtins.filter builtins.pathExists ([
  "${directory}/machines/${name}/configuration.nix"
] ++ lib.optionals (_class == "nixos") [
  "${directory}/machines/${name}/hardware-configuration.nix"
  "${directory}/machines/${name}/disko.nix"
]);
```

So a machine dir just works — no import list. But Nix evaluates from
the git tree: **`git add machines/<name>/disko.nix` before any eval**.

**2. The disko module arrives via clan-core, not from this flake.**
clan-core's `nixosModules/flake-module.nix` pulls
`inputs.disko.nixosModules.default` into `clanCore`, so a clan flake
does not declare its own disko input. This repo's `flake.lock` has a
`disko` node following `clan-core/nixpkgs` (pinned rev `ff8702b`,
2026-06): disko version = whatever clan-core pins; bumping disko
independently is not possible without bumping clan-core. (A non-clan
flake would do it manually:
`inputs.disko.url = "github:nix-community/disko/latest";` +
`inputs.nixpkgs.follows`, and `modules = [ disko.nixosModules.disko ];`.)

What the module injects here (verified by eval on `kamrui-h1`, which
sets no `fileSystems` and no `boot.loader.grub.devices` anywhere):

```
fileSystems."/"    -> /dev/disk/by-partlabel/disk-main-root
fileSystems."/boot"-> /dev/disk/by-partlabel/disk-main-ESP
boot.loader.grub.devices = ["/dev/disk/by-id/nvme-G932E1Q_1T_..."]
```

Bootloader split in this repo: `flake-parts/default.nix` sets the
grub defaults (`enable`, `efiSupport`, `efiInstallAsRemovable =
true`) for every machine; disko fills `boot.loader.grub.devices`
automatically from each disk's `EF02` partition; a few machines set
extra grub bits inside `disko.nix` itself (`machines/nixos/disko.nix`
re-sets `efiInstallAsRemovable`). Don't add `systemd-boot` config on
top — the fleet boots grub.

### The home repo's worked examples

| Machine | Layout | Teaches |
|---|---|---|
| `machines/ghost/disko.nix` | 2 disks: ESP + ext4 root, second whole-disk swap | `/dev/disk/by-id` naming, separate swap disk, `-L` labels |
| `machines/kamrui-h1/disko.nix` | ESP + swap + btrfs subvolumes (`@root`/`@nix`/`@home`/per-user), `compress=zstd:N` | the btrfs subvolume layout this fleet standardizes on |
| `machines/nixos/disko.nix` | NVMe btrfs root + 2 data disks (ext4) | mounting **existing** partitions by matching partlabels; formatting-only specs; `nofail` data mounts |
| `machines/hp-notebook/disko.nix` | single eMMC: EF02 + ESP + ext4 | minimal single-disk |
| `machines/nixos-installer/disko.nix` | USB stick | install media target |

The `machines/nixos/disko.nix` pattern for adopting pre-existing disks
(read its comments in full): the disko `disk.<name>` names were chosen
to match the partlabels the partitions already have
(`disk-sata-sata`, `disk-sdb-data`), so the module's generated
`fileSystems` entries resolve to the existing partitions and normal
rebuilds just mount them; reformatting happens only if you run the
disko CLI against those disks.

## Rebuild vs format

- `nixos-rebuild` / `fh apply` / `clan machines update` only evaluate
  the module: they **mount**, never format. Running them with a
  modified `disko.nix` does not repartition.
- Formatting happens only when the disko CLI runs — during
  `clan machines install` (its default phases are
  `kexec,disko,install,reboot`), via nixos-anywhere, or manually
  (`sudo disko --mode destroy,format,mount ...`; the CLI is in the
  devenv shell via the `disko` package).
- Editing the layout of an installed machine = wipe + reinstall
  (house rule in AGENTS.md). Additive changes are possible the way the
  nixos machine does it (spec matching existing partlabels).
- The generated scripts also live as NixOS outputs, useful for
  dry-running: `nix build .#nixosConfigurations.<host>.config.system.build.diskoScript`
  then inspect before running on the target.

## Filesystem recipes

### ext4 (`ghost`, `nixos` data disks)

```nix
content = {
  type = "filesystem";
  format = "ext4";
  mountpoint = "/";
  mountOptions = ["noatime"];
  extraArgs = ["-L" "nixos"];     # mkfs.ext4 args
};
```

Swap: either a partition (`content.type = "swap"; discardPolicy =
"both";` — kamrui-h1) or a whole second disk as one swap partition
(ghost's `swap` disk, `mountOptions = ["noatime" "nofail"]`).

### btrfs with subvolumes (`kamrui-h1`, `nixos` root)

```nix
content = {
  type = "btrfs";
  extraArgs = ["--force" "--label root"];   # mkfs.btrfs args
  subvolumes = {
    "@root" = {
      mountpoint = "/";
      mountOptions = ["compress=zstd:3" "noatime"];
    };
    "@nix"   = { mountpoint = "/nix";  mountOptions = ["compress=zstd:5" "noatime"]; };
    "@home"  = { mountpoint = "/home"; mountOptions = ["compress=zstd:6" "noatime"]; };
    # swapfile inside a subvolume (generates swapDevices):
    "/swap"  = { mountpoint = "/.swapvol"; swap.swapfile.size = "20M"; };
  };
};
```

Notes: each subvolume becomes its own `fileSystems.<mountpoint>` with
`subvol=` options; the btrfs *type* is single-device — for multi-device
btrfs see the redundancy section; `@`-prefixed names keep `btrfstune`/
snapshot tooling conventions.

### zfs

`disko.devices.zpool.<pool>` pulls members from any partition whose
content is `{ type = "zfs"; pool = "<pool>"; }`. Root-on-ZFS layout
(disko `example/zfs.nix` + clan's disk-encryption guide):

```nix
zpool = {
  zroot = {
    type = "zpool";
    mode = "mirror";                          # omit for single-disk stripe
    options.cachefile = "none";               # avoids "cannot import" in tests/headless
    rootFsOptions = {
      compression = "zstd";                   # clan guide uses "lz4"
      acltype = "posixacl";
      xattr = "sa";
      "com.sun:auto-snapshot" = "true";
      mountpoint = "none";                    # root pool: datasets mount themselves
    };
    datasets = {
      "root" = {
        type = "zfs_fs";
        options = {
          mountpoint = "none";
          encryption = "aes-256-gcm";         # native encryption — see vars section
          keyformat = "passphrase";
          keylocation = "file:///run/partitioning-secrets/per-machine/<m>/zfs/key";
        };
      };
      "root/nixos" = { type = "zfs_fs"; mountpoint = "/";     options.mountpoint = "/"; };
      "root/home"  = { type = "zfs_fs"; mountpoint = "/home"; options.mountpoint = "/home"; };
      "root/tmp"   = { type = "zfs_fs"; mountpoint = "/tmp";  options = { mountpoint = "/tmp"; sync = "disabled"; }; };
      # optional swap zvols / encrypted volumes: type = "zfs_volume" + content.filesystem
    };
  };
};
```

Mechanics to know:

- `mountpoint` in NixOS config vs `options.mountpoint` in ZFS must
  agree; datasets with `options.mountpoint = "none"` are not mounted.
- disko's test example ends with a `postCreateHook` that snapshots
  `zroot@blank` so tests can roll back — harmless to keep, useful for
  VM tests.
- clan-core (`clanCore/zfs.nix`) defaults `networking.hostId =
  "8425e349"` (same as the installer ISO → imports without
  `zpool import -f`), `boot.zfs.forceImportRoot = false`, plus zfs
  autoSnapshot (monthly = 1) and autoScrub. Every ZFS machine shares
  that hostId — fine for boot-time import; give machines unique hostIds
  if you'll ever import two pools cross-machine (iSCSI/NFS scenarios).
- Non-root ZFS (`example/non-root-zfs.nix`) mounts data pools without
  boot involvement.
- zfs needs `boot.supportedFilesystems = ["zfs"]` (or the clan zfs
  defaults cover root pools) and the kernel module in initrd for root
  pools — disko's generated config handles the boot initrd bits via
  `boot` injection.

## LUKS

The `luks` content type wraps anything:

```nix
partitions.root = {
  size = "100%";
  content = {
    type = "luks";
    name = "crypted";
    settings = {
      allowDiscards = true;          # TRIM through the container (SSDs)
      keyFile = "/tmp/secret.key";   # install-time key; ALSO merged into boot.initrd.luks
    };
    additionalKeyFiles = ["/tmp/second.key"];   # extra keyslots added at format
    extraFormatArgs = ["--pbkdf" "argon2id"];
    content = { type = "btrfs"; /* subvolumes */ };
  };
};
```

Semantics worth knowing (from `lib/types/luks.nix`):

- Key selection order: `settings.keyFile` → `passwordFile` (install
  prompt file) → `askPassword` (interactive, the default when neither
  is set) → deprecated top-level `keyFile`.
- `settings` is passed verbatim to `cryptsetup luksFormat`/`open` AND
  merged into the generated
  `boot.initrd.luks.devices.<name>` entry (that is how
  `keyFile`/`allowDiscards`/`fallbackToPassword` reach stage 1) —
  anything you put in `settings` must make sense at **boot**, not just
  at format time.
- `passwordFile` is format-time only; it does **not** leak into the
  generated boot config.
- `initrdUnlock = true` (default) is what adds the
  `boot.initrd.luks.devices` entry; `enrollFido2` switches to
  `systemd-cryptenroll` FIDO2/`crypttabExtraOpts` and forces
  `boot.initrd.systemd.enable`.
- The generated initrd unlock comes from NixOS, so all NixOS LUKS
  options (`fallbackToPassword`, TPM2, ...) work through `settings`.

### Encrypted disks with clan vars

The clan-documented pattern (disk-encryption guide) uses **ZFS native
encryption + a var-generated key + remote decryption over initrd SSH**.
Three moving parts, all in `machines/<m>/disko.nix` + `initrd.nix`:

**1. Key generator pinned to the partitioning phase:**

```nix
clan.core.vars.generators.zfs = {
  files.key.neededFor = "partitioning";   # uploaded BEFORE the disko phase
  runtimeInputs = [pkgs.xkcdpass];
  script = ''xkcdpass -d - -n 8 | tr -d '\n' > $out/key'';
};
```

`neededFor` (verified in clan-core `generic-generator.nix`, default
`"services"`) decides when a var is decrypted on the target:

| neededFor | Deployed | Runtime path (both age & sops backends) |
|---|---|---|
| `partitioning` | before the `disko` install phase only | `/run/partitioning-secrets/<rel_dir>/<file>` |
| `activation` | before `nixos-rebuild`/`nixos-install` | `<secret upload dir>/activation/<rel_dir>/<file>` |
| `users` | before users/groups exist | `/run/user-secrets/...` |
| `services` (default) | with services | `/run/secrets/...` |

Always reference the path through the option
(`${config.clan.core.vars.generators.<g>.files.<f>.path}`) — never
hardcode `/run/partitioning-secrets/...` strings (the doc examples
hardcode an older, shorter layout).

**2. ZFS dataset keylocation + an initrd wait-loop:**

```nix
"root" = {
  type = "zfs_fs";
  options = {
    encryption = "aes-256-gcm";
    keyformat = "passphrase";
    keylocation = "file://${config.clan.core.vars.generators.zfs.files.key.path}";
  };
  mountpoint = "/";
};
# stall boot until the key file appears (delivered via initrd SSH):
boot.initrd.systemd.services.zfs-import-zroot = {
  preStart = ''
    while [ ! -f ${config.clan.core.vars.generators.zfs.files.key.path} ]; do sleep 1; done
  '';
  unitConfig.StartLimitIntervalSec = 0;
  serviceConfig = { RestartSec = "1s"; Restart = "on-failure"; };
};
```

**3. Initrd SSH so the key can be delivered remotely** (separate
`machines/<m>/initrd.nix`, imported from `configuration.nix`):

```nix
boot.initrd.systemd.enable = true;
clan.core.vars.generators.initrd-ssh = {
  files."id_ed25519".neededFor = "activation";
  files."id_ed25519.pub".secret = false;
  runtimeInputs = [pkgs.coreutils pkgs.openssh];
  script = ''ssh-keygen -t ed25519 -N "" -f $out/id_ed25519'';
};
boot.initrd.network = {
  enable = true;
  ssh = {
    enable = true;
    port = 7172;
    authorizedKeys = ["<operator pub key>"];
    hostKeys = [config.clan.core.vars.generators.initrd-ssh.files.id_ed25519.path];
  };
};
boot.initrd.kernelModules = ["e1000e"];   # the NIC's driver (lspci -k)
```

Install (from the installer, after `ssh-copy-id` + `blkdiscard` of the
target disk), then unlock after every boot:

```bash
clan machines install <m> --target-host root@nixos-installer.local --phases kexec,disko
clan machines install <m> --target-host root@nixos-installer.local --phases install
# after reboot — deliver the key over initrd ssh (runs per boot):
clan vars get <m> zfs/key | ssh -p 7172 root@<ip> \
  "mkdir -p /run/partitioning-secrets/per-machine/<m>/zfs && cat > /run/partitioning-secrets/per-machine/<m>/zfs/key.tmp && mv /run/partitioning-secrets/per-machine/<m>/zfs/key{.tmp,}"
```

Design consequence: with this scheme the key **never persists on the
machine's disk** — it is re-delivered per boot (automate `decrypt.sh`
from another always-on box). If that is too much operational overhead
for a desktop-class machine, the lighter variant is a keyfile that
*lives on the disk*: give the same generator a second file with
`neededFor = "activation"` and mount the unlocked dataset by passphrase
slot instead.

**LUKS + vars translation** (derived from the same `neededFor`
semantics — no dedicated clan guide exists):

```nix
clan.core.vars.generators.disk-key = {
  files.format-key.neededFor = "partitioning";   # exists during disko phase
  files.boot-key.neededFor = "activation";       # stable path, from first activation on
  runtimeInputs = [pkgs.xkcdpass];
  script = ''xkcdpass -d - -n 8 | tr -d '\n' > $out/format-key; cp $out/format-key $out/boot-key'';
};
# disko side: format-time key via passwordFile (does NOT leak into boot config)
# ... content = {
#       type = "luks"; name = "crypted";
#       passwordFile = config.clan.core.vars.generators.disk-key.files.format-key.path;
#       settings = { allowDiscards = true; fallbackToPassword = true; };
#       additionalKeyFiles = [config.clan.core.vars.generators.disk-key.files.boot-key.path];
#     };
# boot side: bootloader appends the activation-phase key into the initrd
boot.initrd.secrets."/etc/luks-key" =
  config.clan.core.vars.generators.disk-key.files.boot-key.path;
boot.initrd.luks.devices.crypted.keyFile = "/etc/luks-key";
```

This works because this fleet boots **grub**, which sets
`boot.loader.supportsInitrdSecrets = true`: instead of embedding
secrets in the store-built initrd, grub's installer runs
`append-initrd-secrets` at activation, copying `boot.initrd.secrets`
sources (which exist by then — activation vars deploy before
`nixos-rebuild`) into the installed initrd. Never put a real secret
under `boot.initrd.systemd.contents`/store paths — world-readable
store. Prefer passphrase-prompt + initrd SSH (pattern above) where
"key on the same disk" is unacceptable.

## Two-disk redundancy (mirrored NVMe pairs)

For critical machines (e.g. a k8s node with 2 NVMe) you want: if one
NVMe dies, the box keeps running and boots after power loss. Three
source-verified designs, in order of preference for this fleet:

**1. mdadm RAID1 across both disks, mirrored ESP (disko
`example/boot-raid1.nix` / `luks-on-mdadm.nix`):**

```nix
disko.devices = {
  disk = lib.genAttrs ["first" "second"] (name: {
    type = "disk";
    device = "/dev/disk/by-id/<nvme-${name}>";
    content = {
      type = "gpt";
      partitions = {
        boot = { size = "1M"; type = "EF02"; };        # grub on BOTH disks
        ESP = {
          size = "1G"; type = "EF00";
          content = { type = "mdraid"; name = "boot"; };  # ESP is RAID1
        };
        root = { size = "100%"; content = { type = "mdraid"; name = "root"; }; };
      };
    };
  });
  mdadm = {
    boot = {
      type = "mdadm"; level = 1;
      metadata = "1.0";                                # superblock at END: ESP stays firmware-readable
      content = { type = "filesystem"; format = "vfat"; mountpoint = "/boot"; mountOptions = ["umask=0077"]; };
    };
    root = {
      type = "mdadm"; level = 1;
      content = { type = "gpt"; partitions.primary = {
        size = "100%";
        content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; mountOptions = ["noatime"]; };
      };};
    };
  };
};
```

Why this shape: `metadata = "1.0"` keeps the md superblock out of the
FAT data area so UEFI/grub can still read the ESP while it is a
degraded mirror; the `EF02` partition on both disks means grub installs
to both MBRs (grub reads md v1.0 superblocks). This fleet's grub
default (`efiInstallAsRemovable`) composes fine with it. systemd-boot
is the wrong bootloader for mirrored ESPs — stick with the repo's grub.
LUKS stacks on top of either array
(`luks-on-mdadm.nix`: mdadm root → `content.type = "luks"` →
filesystem); with btrfs the member order matters — disko formats
members alphabetically and btrfs needs all devices present, so see
`example/luks-btrfs-raid.nix` (first disk = "empty" luks member, second
disk's btrfs `extraArgs` appends `/dev/mapper/<first>` and `-d raid1`).

Recovery: degraded boot "just works" (mdadm assembles with 1 member);
after swapping the disk, re-apply the layout
(`clan machines install`/disko CLI on the new disk or `mdadm --add
/dev/md/root /dev/disk/by-id/<new>` and let it resync).

**2. ZFS mirror (clan disk-encryption guide "Raid 1" variant):**
both disks' root partitions join `zroot` (`mode = "mirror"`), ESP only
on the first disk, and `boot.loader.grub.devices` lists **both**
by-ids (grub MBR on both). Composes with the encrypted-root pattern
above unchanged (one pool, one key). Survives a dead NVMe for I/O and
boot; replace with `zpool replace zroot /dev/disk/by-id/<dead>
/dev/disk/by-id/<new>`. If the *first* disk (the one holding the ESP)
dies, the box keeps running but won't boot until an ESP is recreated —
mirror the ESP too (mdraid v1.0 as above) if unattended boot after
single-disk failure is a requirement.

**3. btrfs raid1:** btrfs's type is single-device in disko, so real
raid1 needs mdadm underneath, or the `luks-btrfs-raid.nix`
`extraArgs`-multi-device trick (`-d raid1` with the first device
passed explicitly). Two-disk btrfs raid1 is a valid mirror profile but
the mdadm/ZFS paths above are simpler to reason about and better
covered by examples/tests.

**Kubernetes specifics (k3s nodes):** mirror the *system* pool (this
is what buys "NVMe dies → node keeps running": root, `/nix`,
`/var/lib/rancher`, containerd state all live on the mirror). Data
redundancy for workloads stays at the storage layer — Longhorn
replicas (this repo's `longhorn.nix` module; needs `dm_crypt` for
volume encryption, which it already sets). Do not put etcd/k3s state
on a non-mirrored data disk. RAID of any kind is not a backup: pool
mirrors protect against *hardware* death only, not deletion/VM-level
failures — keep clan backups for that.

## Gotchas

- **`disko.nix` is install-time truth** — after install, edits are
  mount-config only (and must keep matching on-disk partlabels, like
  the nixos machine does) or the machine gets reinstalled.
- **Never write `fileSystems` for disko-managed mountpoints** — the
  module already generates them; duplicates fail eval or double-mount.
  (`machines/nixos/configuration.nix` documents this for `/mnt/sata`,
  `/mnt/hdd`.)
- **`git add` before eval** — untracked `disko.nix`/new machine dirs
  are invisible to every nix command (clan evaluates from the git
  tree).
- **Disk identity** — always `/dev/disk/by-id/...`; kernel names
  (`/dev/nvme0n1`) reorder across boots/hardware changes.
- **`destroy`/`--yes-wipe-all-disks` are unrecoverable** — run only on
  the intended target; prefer `clan machines install` phases which
  scope the disks to the spec.
- **ZFS hostId** — clan's shared default `8425e349` makes pool import
  frictionless on boot; give unique `networking.hostId` when pools must
  move between machines.
- **`settings.keyFile` vs `passwordFile`** — `keyFile` (inside
  `settings`) also ends up in `boot.initrd.luks.devices`; use
  `passwordFile` for install-only secrets.
- **Installer images** — set `disko.enableConfig = false` on machines
  that run disko but don't boot from the disks they format (the
  clanServices `machine-type` iso role already carries disko for
  exactly this reason).
- **flake CLI resolution** — `disko --flake .#<host>` finds
  `.diskoConfigurations.<host>` or the machine's disko config under
  `.nixosConfigurations.<host>`; both work with clan machine dirs.
- **Disk images for tests** — `system.build.diskoImagesScript` +
  `imageSize`; pass LUKS keys with `--pre-format-files` (they land in
  the VM's `/tmp` during formatting).
