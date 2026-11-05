# Gaming as a second boot entry. The default entry is the developer
# system: the machine's own config with the jovian module off. The
# "gaming" specialisation turns jovian on (Valve kernel unless the machine
# pins one, Steam, gamescope, zram, scx, ntsync, the boot power profile)
# and stops the services the Kubernetes clan services
# (external-systems/clanServices k3s, rke2, routed-fabric) enable: HAProxy,
# k3s, rke2 and every FRR daemon. Networking (netif/IfState, WireGuard,
# dummy interfaces) stays as the machine defines it in both entries. It only
# composes modules the fleet already has; pick the entry in the boot menu
# (a kernel change needs a reboot).
#
# A machine that enables this must not set hostSpec.system.jovian.enable
# itself: this module owns it. Nested specialisations are ignored by NixOS,
# so the dev tag's warp/tailscale entries exist only for the developer
# system.
{lib, ...}: {
  flake.nixosModules.gaming-specialisation = {
    config,
    options,
    ...
  }: let
    cfg = config.hostSpec.system.gamingSpecialisation;

    # Every FRR daemon the nixpkgs module offers (bgpd, bfdd, ospfd, ...),
    # read from its options so new daemons are covered too. Removed options
    # (zebra, always on with FRR) are invisible stubs that reject any
    # definition, so they are skipped.
    frrDaemons = lib.filter (
      name: let
        opt = options.services.frr.${name};
      in
        opt ? enable && (opt.enable.visible or true) != false
    ) (lib.attrNames options.services.frr);
  in {
    options.hostSpec.system.gamingSpecialisation = {
      enable = lib.mkEnableOption ''
        a "gaming" boot entry (NixOS specialisation) next to the default
        developer system; see this file's header
      '';
      diskSwap = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          Whether disk swap (the disko swap partition) is used only in the
          gaming entry, so the developer entry runs without it as kubelet
          wants. Off by default: no machine runs Kubernetes yet, so swap
          stays as the machine defines it in both entries.
        '';
      };
      active = lib.mkOption {
        type = lib.types.bool;
        default = false;
        internal = true;
        description = "True inside the gaming specialisation; set by this module, never by a machine.";
      };
    };

    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
        specialisation.gaming.configuration.hostSpec.system.gamingSpecialisation.active = true;
        hostSpec.system.jovian.enable = cfg.active;
      }
      # The parent's definitions are re-evaluated inside the specialisation
      # with active = true, so these drop out there without a mkForce fight.
      (lib.mkIf (!cfg.active && cfg.diskSwap) {
        swapDevices = lib.mkForce [];
      })
      (lib.mkIf cfg.active {
        services = {
          haproxy.enable = lib.mkForce false;
          k3s.enable = lib.mkForce false;
          rke2.enable = lib.mkForce false;
          frr = lib.genAttrs frrDaemons (_: {enable = lib.mkForce false;});
        };
      })
    ]);
  };
}
