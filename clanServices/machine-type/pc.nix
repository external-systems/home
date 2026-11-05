{
  config,
  lib,
  pkgs,
  ...
}: {
  config = {
    # --- hostSpec options --- #
    hostSpec = {
      networking.tailscale.systray = true;
      # Bluetooth comes from facter.json (modules' hostSpec.hardware.bluetooth).
      hardware.sound.enable = true;
      services = {
        kde.enable = true;
        onepassword = {
          enable = true;
          # Include each machine's desktop users without granting access to
          # accounts that only exist elsewhere in the fleet.
          polkitPolicyOwners = lib.attrNames (lib.filterAttrs (_: user: user.isNormalUser) config.users.users);
        };
        wayland.enable = true;
      };
    };
    environment.systemPackages = with pkgs;
    with kdePackages; [
      video-downloader # download youtube videos
      krunner
      kate # text editor
      kcharselect # Tool to select and copy special characters from all installed fonts
      kcolorchooser # A small utility to select a color
      kolourpaint # Easy-to-use paint program
      ktorrent # Powerful BitTorrent client
      filelight # disk usage analyzer
      kalk # Calculator
      xclip # Tool to access the X clipboard from a console application
      zen-browser
      discord
      spotify
      prismlauncher
      tor-browser
      obsidian
      mediawriter
      # rewaita
    ];
  };
}
