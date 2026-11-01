# euc-hel-0 (ex borg helsinki-manager-1). borg's 2026-09-30 thin-pool
# design, reworked for the home reinstall: the two NVMe drives are
# mirrored so the machine boots and runs with either one dead; /nix has
# its own thin LV; the host postgres LVs are gone (embedded etcd).
#
# Hardware (machines/euc-hel-0/facter.json, by-id paths):
#   2x Samsung PM983 960G NVMe  (~894 GiB each) — mdadm RAID1: OS + fast
#     tier (~894 GiB usable)
#   2x Samsung PM883 480G SATA  (~446 GiB each) — bulk tier (one VG per
#     drive: a dead SATA kills only its own pool's data, and drives can
#     be wiped/replaced independently).
#
# NVMe layout, identical on both drives:
#   EF02 1M     GRUB BIOS core (grub installs to both drives)
#   ESP  1G     md "boot": RAID1, metadata 1.0 (superblock at the end,
#               so firmware sees a plain vfat ESP on either drive)
#   os   520G   md "os"   → vg_nixos: root + /nix thin LVs
#   fast rest   md "fast" → vg_fast: the OpenEBS fast thin pool
# OS and the OpenEBS pool are separate arrays and VGs, so a full pool
# can never freeze the OS. Replacing a dead drive: partition it like
# its twin (sgdisk -R), `mdadm --add` each array's partition, and
# rebuild once to reinstall GRUB on it.
#
# LVM thin pools are named <vgname>_thinpool — the OpenEBS lvm-localpv
# convention: an SC carrying volGroup+thinPool adopts that pool; a pool
# NOT named this way (or a missing thinPool param) makes the driver
# auto-create its own pool sized after the first PVC.
#
# Thin pools are deliberately thin-PROVISIONED: thin pools cannot
# shrink, so unclaimed space stays unclaimed. No swap (kubelet). fstrim
# runs from configuration.nix; pool and array monitoring is external.
#
# Install-time truth: editing this file after install requires wiping
# and reinstalling the machine (normal rebuilds only mount).
{
  disko.devices = {
    disk = {
      # NVMe mirror halves (layout above).
      nvme0 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-SAMSUNG_MZQLB960HAJR-00007_S437NC0R208421";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
              priority = 1;
            };
            ESP = {
              size = "1G";
              type = "EF00";
              priority = 2;
              content = {
                type = "mdraid";
                name = "boot";
              };
            };
            os = {
              size = "520G";
              priority = 3;
              content = {
                type = "mdraid";
                name = "os";
              };
            };
            fast = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "fast";
              };
            };
          };
        };
      };
      nvme1 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-SAMSUNG_MZQLB960HAJR-00007_S437NC0R208313";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
              priority = 1;
            };
            ESP = {
              size = "1G";
              type = "EF00";
              priority = 2;
              content = {
                type = "mdraid";
                name = "boot";
              };
            };
            os = {
              size = "520G";
              priority = 3;
              content = {
                type = "mdraid";
                name = "os";
              };
            };
            fast = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "fast";
              };
            };
          };
        };
      };
      # Bulk tier: one VG + thin pool PER DRIVE (blast radius of a dead
      # drive = its own pool; per-drive replacement independence).
      bulk0 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-SAMSUNG_MZ7LM480HCHP-00003_S1YJNXAH300727";
        content = {
          type = "gpt";
          partitions = {
            primary = {
              size = "100%";
              content = {
                type = "lvm_pv";
                vg = "vg_bulk0";
              };
            };
          };
        };
      };
      bulk1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-SAMSUNG_MZ7LM480HCHP-00003_S1YJNXAH300744";
        content = {
          type = "gpt";
          partitions = {
            primary = {
              size = "100%";
              content = {
                type = "lvm_pv";
                vg = "vg_bulk1";
              };
            };
          };
        };
      };
    };
    mdadm = {
      boot = {
        type = "mdadm";
        level = 1;
        metadata = "1.0";
        content = {
          type = "filesystem";
          format = "vfat";
          mountpoint = "/boot";
          mountOptions = ["umask=0077" "noatime"];
        };
      };
      os = {
        type = "mdadm";
        level = 1;
        content = {
          type = "lvm_pv";
          vg = "vg_nixos";
        };
      };
      fast = {
        type = "mdadm";
        level = 1;
        content = {
          type = "lvm_pv";
          vg = "vg_fast";
        };
      };
    };
    lvm_vg = {
      # OS (md "os", ~520G): one thin pool, separate thin LVs so a full
      # nix store (CI builds) can't fill / (and later /var/lib/rancher,
      # kubelet's disk). Both are lvextend-able.
      vg_nixos = {
        type = "lvm_vg";
        lvs = {
          vg_nixos_thinpool = {
            size = "100%FREE";
            lvm_type = "thin-pool";
            extraArgs = ["--poolmetadatasize" "1G"];
          };
          root = {
            size = "100G";
            lvm_type = "thinlv";
            pool = "vg_nixos_thinpool";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = ["noatime"];
              extraArgs = ["-L" "nixos"];
            };
          };
          nix = {
            size = "400G";
            lvm_type = "thinlv";
            pool = "vg_nixos_thinpool";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/nix";
              mountOptions = ["noatime"];
              extraArgs = ["-L" "nix"];
            };
          };
        };
      };
      # Fast tier (md "fast", ~373G): the OpenEBS fast thin pool. 320G,
      # not 100%FREE, leaves room to grow it; thin pools can't shrink.
      vg_fast = {
        type = "lvm_vg";
        lvs = {
          vg_fast_thinpool = {
            size = "320G";
            lvm_type = "thin-pool";
            extraArgs = ["--poolmetadatasize" "1G"];
          };
        };
      };
      # Bulk tier: one thin pool per drive, 100%FREE each.
      vg_bulk0 = {
        type = "lvm_vg";
        lvs = {
          vg_bulk0_thinpool = {
            size = "100%FREE";
            lvm_type = "thin-pool";
            extraArgs = ["--poolmetadatasize" "1G"];
          };
        };
      };
      vg_bulk1 = {
        type = "lvm_vg";
        lvs = {
          vg_bulk1_thinpool = {
            size = "100%FREE";
            lvm_type = "thin-pool";
            extraArgs = ["--poolmetadatasize" "1G"];
          };
        };
      };
    };
  };
}
