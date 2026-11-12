{secrets, ...}: let
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
    # Mail they send: https://mail.odoo.localhost (Mailpit).
    # LAN clients (a Windows laptop): http://<beelink's IP>/hosts.txt into the
    # hosts file, http://<beelink's IP>/ca.crt trusted once.
    # Login: admin / `clan vars get beelink odoo-passwords/admin-password`.
    # Reset one (seconds): `sudo odoo-reset demo`; save a state:
    # `sudo odoo-snapshot save demo TAG`.
    services.odoo = {
      enable = true;
      lan = {
        # Whatever address DHCP gives the Wi-Fi; the home LAN may connect,
        # nothing else.
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
