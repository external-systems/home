_: {
  nixpkgs.overlays = [
    (final: _prev: {
      # linux-firmware 20260910 (in clan-core's nixpkgs aff8a0b) ships a
      # DMCUB blob that PSP rejects on this Rembrandt iGPU (Radeon 680M,
      # DCN 3.1.4): "failed to load ucode DMCUB(0x3D)" /
      # LOAD_IP_FW(0x6) status 0xFFFF0008, followed by 100-500
      # "dc_dmub_srv_log_diagnostic_data" console errors per boot.
      # Same 20260910 regression as kamrui-h1 (see its configuration.nix);
      # upstream reverted the blob in 20260916 (linux-firmware a9f025fe,
      # RH bug 2532947). Use the nixpkgs-unstable pin's firmware (20260810,
      # last good) until clan-core's nixpkgs refreshes past 20260916, then
      # remove this overlay.
      linux-firmware = final.unstable.linux-firmware;
    })
  ];
}
