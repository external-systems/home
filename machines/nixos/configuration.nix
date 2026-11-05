{
  inputs,
  lib,
  pkgs,
  secrets,
  ...
}: {
  hostSpec = {
    # Wired LAN with static addresses from the values flake until netif
    # lands.
    networking.shim = let
      inherit (secrets.hosts.nixos.links) lan;
      network = secrets.networks.${lan.network};
    in {
      enabled = true;
      mode = "static";
      inherit (lan) interface ipv4 ipv6;
      gateway4 = network.ipv4.gateway;
      gateway6 = network.ipv6.gateway;
    };

    services = {
      motd.sshMotd = builtins.readFile ./sshMotd.sh;
      flatpak.enable = true;
    };
  };

  nixpkgs = {
    config = {
      cudaSupport = true;
      cudaCapabilities = ["6.1"];
    };
    # CUDA 13 dropped Pascal (compute 6.1); stay on the CUDA 12 set the
    # card and the legacy_580 driver still support.
    overlays = [(final: _: {cudaPackages = final.cudaPackages_12;})];
  };

  # The one machine without useGlobalPkgs: its pkgs set cudaSupport, which
  # would turn every home-manager package with a CUDA variant (Firefox via
  # onnxruntime, whose cuDNN dropped Pascal) into an uncached or broken
  # build. Users here evaluate their own nixpkgs, without CUDA.
  home-manager = {
    useGlobalPkgs = lib.mkForce false;
    sharedModules = [{nixpkgs.overlays = [inputs.org-pkgs.overlays.default];}];
  };

  # GTX 1070 Ti (Pascal): modules' hostSpec.hardware.gpu.nvidia sets
  # itself up from facter.json (driver, closed kernel module, legacy_580,
  # container toolkit, nvtop).
  hardware.nvidia.powerManagement.enable = true;

  boot = {
    # LTS kernel instead of jovian's Valve kernel: Valve only tests that on
    # AMD, and NVIDIA's legacy_580 driver breaks most often on new kernels.
    kernelPackages = pkgs.linuxPackages;
    kernelParams = [
      "video=DP-2:3440x1440@165.00" # for ASUS ultra wide
      "initcall_blacklist=simpledrm_platform_driver_init"
      "nvidia_drm.fbdev=0"
    ];
  };

  # Shared drives group for wife & netsa, on this machine only (gid kept
  # from the old storagebox module so existing files keep their group).
  users = {
    groups.storage-users.gid = 982;
    users = {
      netsa.extraGroups = ["storage-users"];
      wife.extraGroups = ["storage-users"];
    };
  };

  # NOTE: /mnt/sata and /mnt/hdd mounts are managed by the disko NixOS module
  # from disko.devices.disk.sata and .sdb in ./disko.nix (it auto-generates the
  # fileSystems entries using /dev/disk/by-partlabel, which match the existing
  # partitions disk-sata-sata and disk-sdb-data). Do NOT add manual fileSystems
  # entries here for those mountpoints — it would conflict with disko's.

  # Shared Steam games library (Samsung SSD) and shared user drive (2TB HDD).
  # storage-users (gid 982) is shared by wife & netsa.
  # setgid (2775) makes new files inherit the storage-users group;
  # default ACLs (set below) make new files group-writable regardless of
  # umask 022, so both users can install/verify/update each other's games
  # and freely share files under /mnt/hdd.
  systemd.tmpfiles.rules = [
    "d /mnt/sata 0775 root storage-users -"
    "d /mnt/sata/SteamLibrary 2775 root storage-users -"
    "d /mnt/hdd 2775 root storage-users -"
  ];

  systemd.services.shared-drive-acls = {
    description = "Default ACLs for shared storage drives";
    wantedBy = ["multi-user.target"];
    unitConfig.RequiresMountsFor = "/mnt/sata /mnt/hdd";
    path = [pkgs.acl];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      setfacl -m g:storage-users:rwx,d:g:storage-users:rwx /mnt/sata/SteamLibrary
      setfacl -m g:storage-users:rwx,d:g:storage-users:rwx /mnt/hdd
    '';
  };
}
