{
  _class = "clan.service";
  manifest = {
    name = "@andrewthomaslee/tags";
    description = "Hardware and purpose tags: each role switches on the matching hostSpec modules";
    readme = ''
      - `amd` / `intel`: GPU and CPU support.
      - `dev`: developer workstation (docker, storagebox, nix, nix-ld,
        warp/tailscale specialisations).
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
