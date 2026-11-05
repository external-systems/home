# The gaming boot entry. The module itself comes with every machine
# (machine-type's base); the role switches it on and passes the
# per-machine settings from the inventory.
{
  interface = {lib, ...}: {
    options.diskSwap = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = "Use disk swap only in the gaming entry (hostSpec.system.gamingSpecialisation.diskSwap).";
    };
  };

  perInstance = {settings, ...}: {
    nixosModule.hostSpec.system.gamingSpecialisation = {
      enable = true;
      inherit (settings) diskSwap;
    };
  };
}
