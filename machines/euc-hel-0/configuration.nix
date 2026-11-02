# euc-hel-0 — Hetzner Robot bare metal (Xeon W-2295, 2x PM983 960G NVMe,
# 2x PM883 480G SATA; see facter.json). Formerly borg's
# helsinki-manager-1, reinstalled into this fleet as the remote builder
# and CI build box (external-systems/clanServices remote-builder,
# inventory.nix).
#
# facter.json is carried over from borg; disko.nix (install-time truth)
# is borg's layout reworked for this reinstall (NVMe RAID1, SATA ZFS
# mirror).
{
  pkgs,
  secrets,
  ...
}: {
  hostSpec.networking = {
    shim = let
      inherit (secrets.hosts.euc-hel-0.links) public;
      network = secrets.networks.${public.network};
    in {
      enabled = true;
      mode = "static";
      inherit (public) interface ipv4 ipv6;
      gateway4 = network.ipv4.gateway;
      # fe80::1 on Robot: link-local, bound to the interface by the shim.
      gateway6 = network.ipv6.gateway;
    };
    # Large hardware on fast, long paths: generous socket buffer ceiling
    # (module default 32 MiB).
    optimization.bufferMax = 134217728; # 128 MiB
  };

  boot = {
    # NVMe RAID1 (disko.nix). mdmonitor refuses to run without an alert
    # target; log array events to the journal for the external monitoring.
    swraid = {
      enable = true;
      mdadmConf = "PROGRAM ${pkgs.util-linux}/bin/logger";
    };
    # zbulk (disko.nix): the SATA ZFS mirror. No dataset mounts on the
    # host, so import it explicitly; OpenEBS ZFS LocalPV creates volumes
    # under zbulk/openebs.
    supportedFilesystems.zfs = true;
    zfs.extraPools = ["zbulk"];
    # Cap the ARC so it doesn't compete with pods for RAM (16 GiB of 128).
    kernelParams = ["zfs.zfs_arc_max=17179869184"];
  };
  # ZFS refuses to import a pool last used by another host id; any
  # stable 8 hex digits work.
  networking.hostId = builtins.substring 0 8 (builtins.hashString "sha256" "euc-hel-0");

  # Root is a thin LV (disko.nix): the initrd needs the thin-pool tools,
  # and discards keep the pools from filling up.
  services = {
    lvm.boot.thin.enable = true;
    fstrim.enable = true;
    # Monthly scrub: reads every block and repairs from the mirror.
    zfs.autoScrub.enable = true;
  };
}
