_: {
  # Dev + gaming desktop: KDE/Wayland, Steam and the Valve jovian kernel are
  # assumed with jovian (see flake-parts/nixosModules/jovian.nix).
  hostSpec = {
    system.jovian.enable = true;

    services = {
      openshell.gateway.enable = true;
      # Push-to-talk speech-to-text (whisper.cpp, Vulkan on the AMD iGPU).
      # Hotkey: hold Ctrl+Period. C270 webcam mic is the recording source.
      # The push-to-talk keyboard is pinned in ~/.config/whisper-dictation/
      # config.yaml (input_device: /dev/input/event1) — the module is minimal.
      whisper-dictation.enable = true;
    };
  };

  nixpkgs.overlays = [
    (final: _prev: {
      # linux-firmware 20260910 (in clan-core's nixpkgs aff8a0b) ships a
      # yellow_carp_dmcub.bin that PSP rejects on this DCN 3.1.2 GPU:
      # "failed to load ucode DMCUB(0x3D)" -> black screen after vconsole.
      # Upstream reverted the blob in 20260916 (linux-firmware a9f025fe,
      # RH bug 2532947). Use the nixpkgs-unstable pin's firmware (20260810,
      # last good) until clan-core's nixpkgs refreshes past 20260916,
      # then remove this overlay.
      linux-firmware = final.unstable.linux-firmware;
    })
  ];
}
