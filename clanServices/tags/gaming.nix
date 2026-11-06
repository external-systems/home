# The gaming boot entry. The module itself comes with every machine
# (machine-type's base); the role switches it on and passes the
# per-machine settings from the inventory.
{
  interface = {lib, ...}: {
    options = {
      diskSwap = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = "Use disk swap only in the gaming entry (hostSpec.system.gamingSpecialisation.diskSwap).";
      };
      user = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "wife";
        description = ''
          The gaming entry boots into Steam Gaming Mode logged in as this
          user (hostSpec.system.jovian.user). null boots it to the KDE
          login screen. The user must exist on the machine.
        '';
      };
    };
  };

  perInstance = {settings, ...}: {
    nixosModule.hostSpec.system = {
      gamingSpecialisation = {
        enable = true;
        inherit (settings) diskSwap;
      };
      # Only takes effect in the gaming entry, where jovian is on.
      jovian.user = settings.user;
    };
  };
}
