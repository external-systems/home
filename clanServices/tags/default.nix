{
  _class = "clan.service";
  manifest = {
    name = "@andrewthomaslee/tags";
    description = "Purpose tags: each role switches on the matching hostSpec modules";
    readme = ''
      A tag is a trait two or more machines share. What only one machine
      has (its disks, addresses, NVIDIA driver branch, monitors) stays in
      its configuration.nix.

      Three kinds of tags live in inventory.nix:

      - **Machine type** (`pc`, `server`; the machine-type service): one
        per machine.
      - **Purpose** (this service):
        - `dev`: developer workstation (docker, nix, nix-ld,
          warp/tailscale specialisations). Storage Box mounts are per user
          (homeSpec.programs.storagebox in the profiles).
        - `gaming`: a "gaming" boot entry next to the default developer
          system (hostSpec.system.gamingSpecialisation): jovian, Steam and
          the Valve kernel there, with HAProxy, k3s, rke2 and FRR stopped.
          Per machine: `gaming.machines.<m>.settings.diskSwap`.
      - **Users** (`netsa`, `wife`, `matt`; the users instances): which
        accounts exist on the machine.

      Hardware is not a tag; it comes from each machine's facter.json:
      the AMD, Intel and NVIDIA GPU modules and Bluetooth
      (external-systems/modules), Wi-Fi via NetworkManager when there is a
      WLAN controller (the networking shim), and microcode, firmware and
      KVM from nixos-facter. Nested KVM is the kernel default.
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
  };
}
