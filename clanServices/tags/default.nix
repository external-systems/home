{
  _class = "clan.service";
  manifest = {
    name = "@andrewthomaslee/tags";
    description = "Purpose and connectivity tags: each role switches on the matching hostSpec modules";
    readme = ''
      A tag is a trait two or more machines share. What only one machine
      has (its disks, addresses, NVIDIA driver branch, monitors) stays in
      its configuration.nix.

      Three kinds of tags live in inventory.nix:

      - **Machine type** (`pc`, `server`; the machine-type service): one
        per machine.
      - **Purpose and connectivity** (this service):
        - `dev`: developer workstation (docker, nix, nix-ld,
          warp/tailscale specialisations). Storage Box mounts are per user
          (homeSpec.programs.storagebox in the profiles).
        - `gaming`: a "gaming" boot entry next to the default developer
          system (hostSpec.system.gamingSpecialisation): jovian, Steam and
          the Valve kernel there, with HAProxy, k3s, rke2 and FRR stopped.
          Per machine: `gaming.machines.<m>.settings.diskSwap`.
        - `virt`: nested virtualization.
        - `wifi`: NetworkManager with DHCP (the networking shim's wifi
          mode) until netif (external-systems/clanServices) replaces it.
      - **Users** (`netsa`, `wife`, `matt`; the users instances): which
        accounts exist on the machine.

      Hardware is not a tag: the machine-type base sets
      `hostSpec.hardware.gpu.fromFacter`, so the AMD, Intel and NVIDIA GPU
      modules follow each machine's facter.json. Microcode, firmware and
      KVM modules already come from nixos-facter.
    '';
    categories = ["System"];
  };

  roles = {
    dev = {
      perInstance.nixosModule = ./dev.nix;
      description = "Dev Computer";
    };
    gaming =
      import ./gaming.nix
      // {
        description = "Gaming boot entry (jovian specialisation)";
      };
    virt = {
      perInstance.nixosModule = ./virt.nix;
      description = "Virtualization host";
    };
    wifi = {
      perInstance.nixosModule = ./wifi.nix;
      description = "WiFi via NetworkManager (networking shim)";
    };
  };
}
