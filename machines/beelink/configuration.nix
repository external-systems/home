_: {
  # Large hardware on fast, long paths: generous socket buffer ceiling
  # (module default 32 MiB).
  hostSpec = {
    networking.optimization.bufferMax = 134217728; # 128 MiB
    # Local Odoo instances for testing, this machine only: demo data at
    # https://demo.odoo.localhost, an empty database at
    # https://blank.odoo.localhost, both listed at https://odoo.localhost.
    # Login: admin / `clan vars get beelink odoo-passwords/admin-password`.
    # Reset one to a fresh database: `sudo odoo-reset demo`.
    services.odoo = {
      enable = true;
      instances = {
        demo = {};
        blank.demoData = false;
      };
    };
  };
}
