# Headless server: no desktop, nix daemon defaults (gc, flakes, trusted
# caches) from modules' hostSpec.services.nix.
{config, ...}: {
  config = {
    hardware.graphics.enable = false;

    # Tags that contradict a headless server fail evaluation instead of
    # building something half desktop, half server.
    assertions = [
      {
        assertion = !config.hostSpec.services.kde.enable;
        message = "machine-type: ${config.networking.hostName} has both the pc and server roles (tags). Pick one.";
      }
      {
        assertion = !config.hostSpec.system.gamingSpecialisation.enable;
        message = "machine-type: ${config.networking.hostName} is a server with the gaming tag. Gaming needs a desktop (pc).";
      }
    ];
  };
}
