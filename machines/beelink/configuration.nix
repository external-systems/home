_: {
  # Large hardware on fast, long paths: generous socket buffer ceiling
  # (module default 32 MiB).
  hostSpec = {
    networking.optimization.bufferMax = 134217728; # 128 MiB
    # Odoo for evaluation at https://odoo.localhost, this machine only.
    # Login: admin / `clan vars get beelink odoo-passwords/admin-password`.
    services.odoo.enable = true;
  };
}
