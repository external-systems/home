{pkgs, ...}: {
  config = {
    hostSpec = {
      services = {
        docker.enable = true;
        nix.enable = true;
        nix-ld.enable = true;
      };
    };

    # nixos options
    security.sudo.wheelNeedsPassword = false;
    boot.binfmt.emulatedSystems = ["aarch64-linux"];
    # Dev apps for every user of a dev machine (netsa, matt), kept off
    # machines without the tag (hp-notebook). Language tooling (nixd,
    # the nix linters) follows each user's homeSpec.programs.vscodium
    # languages instead.
    environment.systemPackages = with pkgs; [
      python3Minimal
      # Kubernetes
      argocd
      flux9s
      fluxcd
      freelens-bin
      # Databases
      mongodb-compass
      pgadmin4-desktopmode
    ];
  };
}
