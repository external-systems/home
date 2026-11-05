{
  _class = "clan.service";
  manifest = {
    name = "@andrewthomaslee/tags";
    description = "Hardware and purpose tags: each role switches on the matching hostSpec modules";
    readme = ''
      - `amd` / `intel`: GPU and CPU support.
      - `dev`: developer workstation (docker, nix, nix-ld,
        warp/tailscale specialisations). Storage Box mounts are per user
        (homeSpec.programs.storagebox in the profiles).
      - `gaming`: a "gaming" boot entry next to the default developer
        system (hostSpec.system.gamingSpecialisation): jovian, Steam and
        the Valve kernel there, with HAProxy, k3s, rke2 and FRR stopped.
      - `virt`: nested virtualization.

      Networking is no longer a tag: each machine's configuration.nix sets
      `hostSpec.networking.shim` until netif (external-systems/clanServices)
      replaces it.
    '';
    categories = ["System"];
  };

  roles = {
    amd = {
      perInstance.nixosModule = ./amd.nix;
      description = "amd";
    };
    dev = {
      perInstance.nixosModule = ./dev.nix;
      description = "Dev Computer";
    };
    gaming = {
      perInstance.nixosModule = ./gaming.nix;
      description = "Gaming boot entry (jovian specialisation)";
    };
    intel = {
      perInstance.nixosModule = ./intel.nix;
      description = "intel";
    };
    virt = {
      perInstance.nixosModule = ./virt.nix;
      description = "Virtualization host";
    };
  };
}
