_: {
  # One btrfs filesystem (disko: --label root) holds every user's Steam
  # library and shader caches: bees stores identical data once
  # (hostSpec.system.btrfsDedup), whoever owns the files.
  hostSpec.system.btrfsDedup = {
    enable = true;
    filesystems.root.spec = "LABEL=root";
  };

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
}
