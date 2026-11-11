# kamrui-h1: one NVMe disk. Install-time truth: a change here means a
# wipe and `clan machines install kamrui-h1` (documentation:
# fleet/kamrui-h1.md).
#
# - GRUB (BIOS boot partition + EFI system partition).
# - Swap the size of RAM (32 GiB) plus headroom, for hibernation
#   (resumeDevice). zram takes swap first; this one holds the
#   hibernation image.
# - One btrfs filesystem (label root, which bees deduplicates as a
#   whole). Compression is a filesystem-wide mount option: the first
#   subvolume mounted decides it, so every subvolume says the same
#   zstd:1. /nix gets zstd:3 as a btrfs property, which every store path
#   inherits.
# - Subvolumes are what gets its own lifetime: wiped, rolled back or
#   backed up apart from the rest.
{
  disko.devices.disk.main = {
    name = "main-cw3jfbnbpybwr53244io7qtsz6o6zr1e";
    device = "/dev/disk/by-id/nvme-G932E1Q_1T_YALT002964T";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02";
          priority = 1;
        };
        ESP = {
          type = "EF00";
          size = "4G";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = ["umask=0077"];
          };
        };
        swap = {
          size = "36G";
          content = {
            type = "swap";
            discardPolicy = "both";
            resumeDevice = true;
          };
        };
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [
              "--force"
              "--label"
              "root"
              # Block group items in their own tree: faster mounts.
              "--features"
              "block-group-tree"
            ];
            # Runs after each subvolume's mount during install; acts once
            # /mnt/nix is mounted, before nixos-install writes the store.
            postMountHook = ''
              if mountpoint -q /mnt/nix; then
                btrfs property set /mnt/nix compression zstd:3
              fi
            '';
            subvolumes = let
              mountOptions = [
                "compress=zstd:1"
                "noatime"
              ];
            in {
              "@root" = {
                mountpoint = "/";
                inherit mountOptions;
              };
              "@nix" = {
                mountpoint = "/nix";
                inherit mountOptions;
              };
              # Logs survive a root rollback.
              "@log" = {
                mountpoint = "/var/log";
                inherit mountOptions;
              };
              "@home" = {
                mountpoint = "/home";
                inherit mountOptions;
              };
              "@netsa" = {
                mountpoint = "/home/netsa";
                inherit mountOptions;
              };
              "@wife" = {
                mountpoint = "/home/wife";
                inherit mountOptions;
              };
              # Game libraries, /srv/steam/users/<user>
              # (modules: hostSpec.system.gaming.steamSharing.libraryRoot).
              "@steam" = {
                mountpoint = "/srv/steam";
                inherit mountOptions;
              };
              # k3s in the developer entry: its data (containerd images,
              # the server database, manifests), the kubelet's pods and
              # volumes, and persistent volume data (local-path, rawfile).
              # Deleting a subvolume resets that part of the cluster.
              "@k3s" = {
                mountpoint = "/var/lib/rancher";
                inherit mountOptions;
              };
              "@kubelet" = {
                mountpoint = "/var/lib/kubelet";
                inherit mountOptions;
              };
              "@k8s-volumes" = {
                mountpoint = "/var/lib/k8s-volumes";
                inherit mountOptions;
              };
            };
          };
        };
      };
    };
  };
}
