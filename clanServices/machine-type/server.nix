# Headless server: no desktop, nix daemon defaults (gc, flakes, trusted
# caches) from modules' hostSpec.services.nix.
{
  config = {
    hostSpec.services.nix.enable = true;
    # Graphics stacks are pointless without a display.
    hardware.graphics.enable = false;
  };
}
