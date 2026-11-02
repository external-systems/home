# Headless server: no desktop, nix daemon defaults (gc, flakes, trusted
# caches) from modules' hostSpec.services.nix.
{
  config.hardware.graphics.enable = false;
}
