_: {
  # Dev + gaming desktop: KDE/Wayland, Steam and the Valve jovian kernel are
  # assumed with jovian (modules' nixosModules.jovian).
  hostSpec = {
    system.jovian.enable = true;

    # WiFi via NetworkManager (DHCP) until netif lands.
    networking.shim = {
      enabled = true;
      mode = "wifi";
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
}
