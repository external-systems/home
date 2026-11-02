_: {
  # Dev + gaming desktop: KDE/Wayland, Steam and the Valve jovian kernel are
  # assumed with jovian (modules' nixosModules.jovian).
  hostSpec = {
    system.jovian.enable = true;

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

    # Push-to-talk speech-to-text (whisper.cpp, Vulkan on the AMD iGPU).
    # Hotkey: hold Ctrl+Period. C270 webcam mic is the recording source.
    # The push-to-talk keyboard is pinned in ~/.config/whisper-dictation/
    # config.yaml (input_device: /dev/input/event1) — the module is minimal.
    services.whisper-dictation = {
      enable = true;
      user = "netsa";
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
