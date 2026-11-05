# Gaming as a second boot entry. The default entry is the developer
# system: the machine's own config, with the jovian module off and no disk
# swap (kubelet wants swap off). The "gaming" specialisation turns jovian on
# (Valve kernel unless the machine pins one, Steam, gamescope, zram, scx,
# ntsync, the boot power profile), brings back the disko swap partition,
# and stops the developer network services (k3s, FRR's bgpd). It only
# composes modules the fleet already has; pick the entry in the boot menu
# (a kernel change needs a reboot).
#
# A machine that enables this must not set hostSpec.system.jovian.enable
# itself: this module owns it. Nested specialisations are ignored by NixOS,
# so the dev tag's warp/tailscale entries exist only for the developer
# system.
{lib, ...}: {
  flake.nixosModules.gaming-specialisation = {config, ...}: let
    cfg = config.hostSpec.system.gamingSpecialisation;
  in {
    options.hostSpec.system.gamingSpecialisation = {
      enable = lib.mkEnableOption ''
        a "gaming" boot entry (NixOS specialisation) next to the default
        developer system; see this file's header
      '';
      diskSwap = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = ''
          Whether disk swap (the disko swap partition) is used only in the
          gaming entry. The developer entry then runs without disk swap, as
          kubelet wants. False leaves swap as the machine defines it in
          both entries.
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
          k3s.enable = lib.mkForce false;
          frr.bgpd.enable = lib.mkForce false;
        };
      })
    ]);
  };
}
