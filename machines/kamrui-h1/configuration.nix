_: {
  # Bees deduplicates the root btrfs filesystem (disko: --label root):
  # modules' gaming module turns it on for gaming machines whose / is
  # btrfs (hostSpec.system.gaming.dedup), and Steam libraries are
  # /srv/steam/users/<user> (steamSharing.libraryRoot, the default).

  # Large hardware on fast, long paths: generous socket buffer ceiling
  # (module default 32 MiB).
  hostSpec.networking.optimization.bufferMax = 134217728; # 128 MiB

  # Realtek rtw89 Wi-Fi (facter.json): no Wi-Fi power-save or PCIe power
  # management latency spikes. Moved here from the networking shim,
  # since this is the only machine with the driver.
  boot.extraModprobeConfig = ''
    options rtw89_core disable_ps_mode=Y
    options rtw89_pci disable_clkreq=Y disable_aspm_l1=Y
  '';

  # k3s' database (sqlite or etcd) syncs to disk constantly, which
  # copy-on-write fragments: no CoW for it (only new files, so set
  # before k3s first starts). It is small and k3s keeps its own
  # snapshots.
  systemd.tmpfiles.settings.k3s-db."/var/lib/rancher/k3s/server/db" = {
    d = {
      mode = "0700";
      user = "root";
      group = "root";
    };
    h.argument = "+C";
  };
}
