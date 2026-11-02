# TEMPORARY networking shim, until the IfState-based netif clan service
# (external-systems/clanServices) is ready. Each machine's
# configuration.nix sets hostSpec.networking.shim from the values flake
# (`secrets`, the private external-systems/secrets),
# so no address literal lives in this repo. The option shapes mirror the
# values schema (links.<name>.{interface,ipv4,ipv6}, CIDR strings), so
# the switch to netif is a per-machine rewrite of one attrset.
#
# Two modes, matching what the fleet ran before the shim:
# - static: fixed addresses + default routes on one wired interface
#   (scripted networking).
# - wifi: NetworkManager owns the link (DHCP + RA). No static route: the old `wan` tag
#   pinned gateways to an interface name that does not exist on
#   kamrui-h1/beelink (NM ignored it), so it is dropped, not ported.
#
# TCP/Wi-Fi performance tuning is not here: it is the generic
# external-systems/modules nixosModules.networking-optimization, enabled
# fleet-wide by the machine-type service.
{lib, ...}: {
  flake.nixosModules.networking-shim = {config, ...}: let
    cfg = config.hostSpec.networking.shim;
    inherit (lib) mkOption types;

    # "192.0.2.10/24" -> {address = "192.0.2.10"; prefixLength = 24;}
    toAddress = cidr: let
      parts = lib.splitString "/" cidr;
    in {
      address = builtins.head parts;
      prefixLength = lib.toIntBase10 (lib.last parts);
    };
  in {
    options.hostSpec.networking.shim = {
      enabled = lib.mkEnableOption "the temporary networking shim (replaced by netif)";

      mode = mkOption {
        type = types.enum ["static" "wifi"];
        default = "static";
        description = "static: fixed addresses on a wired link; wifi: NetworkManager with DHCP.";
      };

      interface = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Kernel interface name (values: hosts.<machine>.links.<link>.interface). Required in static mode.";
      };

      ipv4 = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Static IPv4 addresses with prefix length, e.g. 192.0.2.10/24 (values: links.<link>.ipv4).";
      };

      ipv6 = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Static IPv6 addresses with prefix length (values: links.<link>.ipv6).";
      };

      gateway4 = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "IPv4 default gateway (values: networks.<network>.ipv4.gateway).";
      };

      gateway6 = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "IPv6 default gateway; link-local gateways (fe80::1) work because the route is bound to the interface.";
      };
    };

    config = lib.mkIf cfg.enabled (lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.mode != "static" || cfg.interface != null;
            message = "hostSpec.networking.shim: static mode needs `interface` (from secrets.hosts.<machine>.links.<link>.interface).";
          }
        ];
      }

      (lib.mkIf (cfg.mode == "static") {
        networking = {
          interfaces.${cfg.interface} = {
            useDHCP = false;
            ipv4.addresses = map toAddress cfg.ipv4;
            ipv6.addresses = map toAddress cfg.ipv6;
          };
          defaultGateway = lib.mkIf (cfg.gateway4 != null) {
            address = cfg.gateway4;
            inherit (cfg) interface;
          };
          defaultGateway6 = lib.mkIf (cfg.gateway6 != null) {
            address = cfg.gateway6;
            inherit (cfg) interface;
          };
        };
      })

      (lib.mkIf (cfg.mode == "wifi") {
        networking.networkmanager.enable = lib.mkDefault true;
      })
    ]);
  };
}
