# kamrui-h1

The AMD gaming and dev desktop (Ryzen 7 6800H, 32 GiB, one 1 TB NVMe),
shared by netsa and wife: KDE with Steam in each one's own session (no
Gaming Mode entry), and a developer boot entry for k3s.

## Disk layout

`machines/kamrui-h1/disko.nix` is install-time truth: changing it means a
wipe and a reinstall.

| Partition | Size | Use |
|---|---|---|
| BIOS boot | 1 MiB | GRUB |
| ESP | 4 GiB | `/boot` (kernels of every boot entry and generation) |
| swap | 36 GiB | Hibernation image (`resumeDevice`); zram takes swap first |
| root | rest | One btrfs filesystem, label `root`, `block-group-tree` |

| Subvolume | Mount | Why its own |
|---|---|---|
| `@root` | `/` | The system |
| `@nix` | `/nix` | The store, compressed at zstd:3 (property) |
| `@log` | `/var/log` | Logs survive a root rollback |
| `@home`, `@netsa`, `@wife` | `/home`, `/home/<user>` | Each user's home on its own |
| `@steam` | `/srv/steam` | Game libraries, `/srv/steam/users/<user>` |
| `@k3s` | `/var/lib/rancher` | k3s data: containerd images, server database (no CoW), manifests |
| `@kubelet` | `/var/lib/kubelet` | Pods' volumes and emptyDirs |
| `@k8s-volumes` | `/var/lib/k8s-volumes` | Persistent volume data |

Deleting `@k3s` and `@kubelet` resets the cluster without touching
anything else; `@k8s-volumes` holds what the cluster's volumes stored.

### Compression

btrfs takes `compress=` from the first subvolume mounted and applies it
to the whole filesystem, so every subvolume mounts with the same
`compress=zstd:1,noatime`: cheap for big game installs and updates, and
zstd decompresses at the same speed at any level. `/nix` is set to
`zstd:3` as a btrfs property during install, before the store is
written; every store path inherits it. Check with:

```sh
btrfs property get /nix/store compression
sudo compsize -x /nix /srv/steam
```

Never `compress-force`: most game data is already compressed, and
btrfs' own check skips it quickly.

## Steam

Every user keeps their own Steam library; games and shader caches are
shared below Steam as reflink copies (modules: Gaming page).

- Libraries: `/srv/steam/users/<user>` (0700, created by tmpfiles). Add
  it once in Steam: Settings > Storage > Add Drive.
- Copy a game: `sudo steam-copy-game --from netsa --to wife <appid>` with
  wife's Steam closed.
- Shader caches sync at boot and every 15 minutes.
- bees deduplicates the whole filesystem in the background, is frozen
  while any Steam game runs, and is capped at 3 GiB of memory including
  its page cache; btrfs is scrubbed monthly.

## Hibernation

The swap partition is the resume device. Resume picks up the entry that
hibernated: after hibernating in the developer entry, choose it again in
the boot menu (its kernel differs from the desktop's Valve kernel, and a
kernel refuses another kernel's image). The developer entry keeps disk
swap (`diskSwap` stays `true` in the gaming tag), so it can hibernate too.

## k3s (developer entry)

k3s goes in through `hostSpec.system.developerSpecialisation.configuration`
(not yet wired). The disk is ready for it:

- **Swap.** Disk swap stays on, so the kubelet needs
  `--kubelet-arg=fail-swap-on=false` and `swapBehavior: LimitedSwap`
  (only Burstable pods may swap).
- **Snapshotter.** k3s' default overlayfs works on btrfs; bees still
  deduplicates image layers across k3s, Docker and Podman.
- **Storage.** k3s' built-in `local-path-provisioner`, pointed at
  `/var/lib/k8s-volumes/local-path`, is the default. For size limits,
  block volumes or VolumeSnapshots add OpenEBS rawfile LocalPV with its
  pool at `/var/lib/k8s-volumes/rawfile` (`WaitForFirstConsumer`); on
  btrfs its snapshots and clones are reflinks. Keep CoW on the pool.
- **Check** that `kubectl describe node` shows the image filesystem's
  capacity: kubelet stats on btrfs subvolumes have had bugs.

## Reinstall

1. Back up what isn't elsewhere: both homes (`~/.local/share/Steam`
   holds logins and settings; games can be downloaded again).
2. Make sure the machine's clan vars are in `vars/` (`clan vars list
   kamrui-h1`), so the install brings its secrets back.
3. Boot the NixOS installer on kamrui-h1 and run, from the devenv shell:

    ```sh
    clan machines install kamrui-h1 --target-host root@<installer address>
    ```

4. After the first login, each user adds `/srv/steam/users/<user>` in
   Steam (Settings > Storage), then installs or copies games.
