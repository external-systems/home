# euc-hel-0 (ex borg helsinki-manager-1) — 4-disk thin-pool layout,
# carried over unchanged from borg (2026-09-30 redesign).
#
# Hardware (machines/euc-hel-0/facter.json, by-id paths):
#   2x Samsung PM983 960G NVMe  (~894 GiB each) — OS + fast tier
#   2x Samsung PM883 480G SATA  (~446 GiB each) — bulk tier (one VG per
#     drive: a dead SATA kills only its own pool's data, and drives can
#     be wiped/replaced independently).
#
# LVM thin pools are named <vgname>_thinpool — the OpenEBS lvm-localpv
# convention: an SC carrying volGroup+thinPool adopts that pool; a pool
# NOT named this way (or a missing thinPool param) makes the driver
# auto-create its own pool sized after the first PVC.
#
# Thin pools are deliberately thin-PROVISIONED (the ~377G of slack in
# vg_nixos is OS headroom, not a PV): thin pools cannot shrink, thick
# LVs grow via lvextend. No swap; fstrim + the thin-pool alert live in
# the fleet lvm-thin module (flipped on by the rke2 clanService).
#
# Install-time truth: editing this file after install requires wiping
# and reinstalling the machine (normal rebuilds only mount).
{
  disko.devices = {
    disk = {
      # OS drive: ESP + vg_nixos (root thinlv inside a thin pool).
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
              size = "16G";
              type = "EF00";
              priority = 2;
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077" "noatime"];
              };
            };
            primary = {
              size = "100%";
              content = {
                type = "lvm_pv";
                vg = "vg_nixos";
              };
            };
          };
        };
      };
      # Fast tier: the ONE host postgres (future kine datastore) gets
      # THICK, predictable LVs (data + WAL separated); the rest is the
      # OpenEBS fast thin pool. The 700G pool size (not 100%FREE)
      # leaves ~145G spare for lvextend of the thick LVs — thin pools
      # can't shrink, so capacity must stay unclaimed.
      nvme1 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-SAMSUNG_MZQLB960HAJR-00007_S437NC0R208313";
        content = {
          type = "gpt";
          partitions = {
            primary = {
              size = "100%";
              content = {
                type = "lvm_pv";
                vg = "vg_fast";
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
    lvm_vg = {
      # OS: thin pool with most of the drive as slack (pure OS headroom
      # — root is a thinlv, snapshots/extension cheap).
      vg_nixos = {
        type = "lvm_vg";
        lvs = {
          vg_nixos_thinpool = {
            size = "100%FREE";
            lvm_type = "thin-pool";
            extraArgs = ["--poolmetadatasize" "1G"];
          };
          root = {
            size = "500G";
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
        };
      };
      # Fast tier: thick host-DB LVs + the OpenEBS fast thin pool.
      vg_fast = {
        type = "lvm_vg";
        lvs = {
          pg-data = {
            size = "32G";
            content = {
              type = "filesystem";
              format = "xfs";
              mountpoint = "/var/lib/postgresql";
              mountOptions = ["noatime"];
            };
          };
          pg-wal = {
            size = "16G";
            content = {
              type = "filesystem";
              format = "xfs";
              mountpoint = "/var/lib/postgresql-wal";
              mountOptions = ["noatime"];
            };
          };
          vg_fast_thinpool = {
            size = "700G";
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
