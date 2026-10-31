{
  inputs,
  pkgs,
  ...
}: {
  config = {
    # --- hostSpec options --- #
    hostSpec = {
      networking.tailscale.systray = true;
      hardware = {
        bluetooth.enable = true;
        sound.enable = true;
      };
      services = {
        kde.enable = true;
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
      inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
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
