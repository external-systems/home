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
        - `dev`: developer workstation (docker, nix, nix-ld, the shared
          dev apps: Kubernetes and database GUIs, python3). Storage
          Box mounts are per user (homeSpec.programs.storagebox in the
          profiles).
        - `gaming`: boot entries for gaming. The default entry runs
          jovian (Valve kernel, Steam on the KDE desktop, GE-Proton by
          default); "gaming" (hostSpec.system.gamingSpecialisation) boots
          into Steam Gaming Mode; "developer"
          (hostSpec.system.developerSpecialisation) has the normal kernel
          and no Steam, for Kubernetes and VPNs later. Every user keeps a
          Steam library of their own in /srv/steam/users/<user>;
          `steam-copy-game` (sudo) copies a game and its shader cache to
          another user, and shader caches are synced between users, both
          as reflink copies. On a btrfs root, bees deduplicates the
          filesystem and pauses while a game runs.
          Per machine (`gaming.machines.<m>.settings`): `gamingEntry =
          false` drops the gaming entry (a desktop several people use),
          `gamingMode` boots the gaming entry into Gaming Mode as the
          locked `gamer` user (off: KDE login screen; `user` overrides
          who), `games` sets per-game Steam settings by App ID
          (compatibility tool, env, wrappers, args) for every user,
          `outputs` picks Gaming Mode's display by connector, `diskSwap =
          false` drops disk swap in the developer entry, `defaultEntry =
          "gaming"` boots Gaming Mode by default with the desktop as the
          "desktop" entry (a Steam Deck).
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
