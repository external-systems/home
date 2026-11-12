{
  lib,
  secrets,
  ...
}: let
  wifi = secrets.hosts.beelink.links.wifi;
  lan = secrets.networks.${wifi.network};
in {
  # Large hardware on fast, long paths: generous socket buffer ceiling
  # (module default 32 MiB).
  hostSpec = {
    networking.optimization.bufferMax = 134217728; # 128 MiB
    # Odoo instances for testing, on this machine and the home LAN (not
    # the internet): demo data at https://demo.odoo.localhost and
    # https://demo.odoo.beelink.home.arpa, an empty database at
    # https://blank.odoo.localhost and https://blank.odoo.beelink.home.arpa.
    # LAN clients (a Windows laptop): `odoo-hosts` lines in the hosts file,
    # http://odoo.beelink.home.arpa/ca.crt trusted once.
    # Login: admin / `clan vars get beelink odoo-passwords/admin-password`.
    # Reset one to a fresh database: `sudo odoo-reset demo`.
    services.odoo = {
      enable = true;
      lan = {
        # The Wi-Fi address without its prefix length; the home LAN may
        # connect, nothing else.
        addresses = map (address: builtins.head (lib.splitString "/" address)) wifi.ipv4;
        interfaces = [wifi.interface];
        allowedClients = [lan.ipv4.cidr];
      };
      instances = {
        demo.expose.lan = true;
        blank = {
          demoData = false;
          expose.lan = true;
        };
      };
    };
  };
}
