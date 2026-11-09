# Office, cloud and remote-desktop apps that netsa and matt both use,
# imported by their home-manager profiles. A user's preference, not a
# machine trait: wife shares kamrui-h1 and nixos with netsa but gets none
# of it, and hp-notebook never downloads it.
{pkgs, ...}: {
  # The fonts below only show up with fontconfig on.
  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    teams-for-linux # Microsoft Teams
    # Word/Excel/PowerPoint look-alike with the best .docx/.xlsx/.pptx
    # fidelity.
    onlyoffice-desktopeditors
    powershell
    # Remote Desktop (RDP) to Windows machines.
    remmina
    # Dropbox: the official client (the package only launches it; the
    # client downloads and updates itself in ~/.dropbox-dist) and
    # Maestral, the open-source client (daemon/CLI and Qt GUI) to fall
    # back on. Let only one of them sync a given folder.
    dropbox
    maestral
    maestral-gui
    # Arial, Times New Roman, Verdana, ... and Calibri, Cambria,
    # Consolas, ...: Office documents render with their own fonts.
    corefonts
    vista-fonts
  ];
}
