# The clan: inventory, home's own clan services, and the arguments every
# machine module receives.
{
  inputs,
  lib,
  self,
  ...
}: {
  # Home's clan services (clanServices/*/flake-module.nix register
  # clan.modules.<name>). Imported at the top level: inside `clan = {}`
  # the import would land at flake.clan.clan.modules.
  imports = [../clanServices/flake-module.nix];

  clan = {
    inventory = import ../inventory.nix {
      inherit lib;
      secrets = inputs.secrets.values;
    };

    # Module arguments for every machine (configuration.nix, clan service
    # nixosModules): `secrets` is the values tree (the private
    # external-systems/secrets), read by
    # nixosModules.networking-shim and the per-machine networking.
    specialArgs = {
      inherit inputs self;
      secrets = inputs.secrets.values;
    };
  };
}
