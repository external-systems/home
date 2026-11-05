_: {
  hostSpec = {
    networking = {
      # WiFi via NetworkManager (DHCP) until netif lands.
      shim = {
        enabled = true;
        mode = "wifi";
      };
      # Large hardware on fast, long paths: generous socket buffer
      # ceiling (module default 32 MiB).
      optimization.bufferMax = 134217728; # 128 MiB
    };
  };

  # Realtek rtw89 Wi-Fi (facter.json): no Wi-Fi power-save or PCIe power
  # management latency spikes. Moved here from the networking shim,
  # since this is the only machine with the driver.
  boot.extraModprobeConfig = ''
    options rtw89_core disable_ps_mode=Y
    options rtw89_pci disable_clkreq=Y disable_aspm_l1=Y
  '';
}
