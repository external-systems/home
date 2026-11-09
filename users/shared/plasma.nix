# The Plasma desktop netsa, matt and wife share: global shortcuts, the
# Windows-style screenshot keys, three numbered virtual desktops and one
# bottom panel on every screen. Read from netsa's hand-made settings with
# plasma-manager's rc2nix, keeping only the deliberate choices.
#
# Everything set here is written again at every login: a shortcut changed
# in System Settings comes back, and the panel layout is rebuilt from this
# file (hand edits to the panel are lost). What is not set here stays
# editable. Per user, never shared: the pinned apps
# (shared.plasma.launchers) and the wallpaper
# (programs.plasma.workspace.wallpaper).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.shared.plasma;
  # One panel system monitor (a KDE preset applet); sensor ids are Plasma's.
  monitor = name: title: chartFace: sensors: colors: {
    name = "org.kde.plasma.systemmonitor.${name}";
    config = {
      Appearance = {inherit title chartFace;};
      Sensors.highPrioritySensorIds = builtins.toJSON sensors;
      SensorColors = colors;
    };
  };
in {
  options.shared.plasma.launchers = lib.mkOption {
    type = with lib.types; nullOr (listOf str);
    default = null;
    example = ["applications:com.mitchellh.ghostty.desktop"];
    description = ''
      This user's apps pinned to the panel's task manager, as
      applications:<desktop file id>. Never shared: each user sets their
      own. null leaves the pins to the user (pinned by hand), but a change
      to the panel in this file rebuilds it with KDE's default pins.
    '';
  };

  config.programs.plasma = {
    # Default wallpaper; a user's profile sets its own to override it.
    workspace.wallpaper = lib.mkDefault "${pkgs.kdePackages.plasma-workspace-wallpapers}/share/wallpapers/Mountain/";

    kwin = {
      virtualDesktops = {
        number = 3;
        rows = 1;
      };
      # Night Color off for everyone, also where it was turned on by hand.
      nightLight.enable = false;
    };

    shortcuts = {
      kwin = {
        # Super+Space maximizes, Super+arrows tile to that side.
        "Window Maximize" = "Meta+Space";
        "Window Minimize" = [];
        "Window Quick Tile Top" = "Meta+Up";
        "Window Quick Tile Bottom" = "Meta+Down";
        "Window Quick Tile Left" = "Meta+Left";
        "Window Quick Tile Right" = "Meta+Right";
        # Super+Shift+arrows send the window to the screen that way; the
        # next/previous-screen defaults gave up Meta+Shift+Left/Right.
        "Window One Screen Up" = "Meta+Shift+Up";
        "Window One Screen Down" = "Meta+Shift+Down";
        "Window One Screen to the Left" = "Meta+Shift+Left";
        "Window One Screen to the Right" = "Meta+Shift+Right";
        "Window to Next Screen" = [];
        "Window to Previous Screen" = [];
        # Super alone opens the overview; the launcher moves to Super+A.
        Overview = "Meta";
        "Switch One Desktop to the Left" = [
          "Meta+Z"
          "Meta+Ctrl+Left"
        ];
        "Switch One Desktop to the Right" = [
          "Meta+X"
          "Meta+Ctrl+Right"
        ];
        # Frees Super+T for the terminal.
        "Edit Tiles" = [];
      };
      plasmashell = {
        "activate application launcher" = "Meta+A";
        "clipboard_action" = "Meta+Ctrl+X";
        "cycle-panels" = [];
        "previous activity" = "Meta+Shift+A";
      };
      # The media, volume and brightness keys keep working; the Ctrl
      # combinations are for keyboards without them.
      mediacontrol = {
        nextmedia = [
          "Media Next"
          "Ctrl+Shift+Right"
        ];
        previousmedia = [
          "Media Previous"
          "Ctrl+Shift+Left"
        ];
      };
      kmix = {
        increase_volume = [
          "Volume Up"
          "Ctrl+Shift+Up"
        ];
        decrease_volume = [
          "Volume Down"
          "Ctrl+Shift+Down"
        ];
      };
      org_kde_powerdevil = {
        "Increase Screen Brightness" = [
          "Monitor Brightness Up"
          "Ctrl+Alt+Up"
        ];
        "Decrease Screen Brightness" = [
          "Monitor Brightness Down"
          "Ctrl+Alt+Down"
        ];
      };
      # Super+T opens Ghostty for users who have it, instead of Konsole's
      # Ctrl+Alt+T.
      "services/com.mitchellh.ghostty.desktop"._launch = lib.mkIf config.homeSpec.programs.ghostty.enable "Meta+T";
      "services/org.kde.konsole.desktop"._launch = lib.mkIf config.homeSpec.programs.ghostty.enable [];
    };

    # Windows-style: Super+Shift+S snips a region, Super+Print the active
    # window; Print keeps KDE's full-screen default.
    spectacle.shortcuts = {
      captureRectangularRegion = [
        "Meta+Shift+S"
        "Meta+Shift+Print"
      ];
      captureActiveWindow = "Meta+Print";
      launchWithoutCapturing = "Ctrl+Shift+P";
    };

    panels = [
      {
        location = "bottom";
        screen = "all";
        floating = true;
        height = 50;
        widgets = [
          "org.kde.plasma.kickoff"
          {
            name = "org.kde.plasma.pager";
            config.General = {
              displayedText = "Number";
              showOnlyCurrentScreen = true;
              showWindowOutlines = false;
              wrapPage = true;
            };
          }
          {
            name = "org.kde.plasma.icontasks";
            config = lib.mkIf (cfg.launchers != null) {
              General.launchers = lib.concatStringsSep "," cfg.launchers;
            };
          }
          (monitor "diskusage" "Disk Usage" "org.kde.ksysguard.horizontalbars" ["disk/all/usedPercent"] {
            "disk/all/usedPercent" = "170,0,255";
          })
          (monitor "net" "Network Speed" "org.kde.ksysguard.linechart" ["network/all/download" "network/all/upload"] {
            "network/all/download" = "61,174,233";
            "network/all/upload" = "233,120,61";
          })
          (monitor "cpu" "Total CPU Use" "org.kde.ksysguard.piechart" ["cpu/all/usage"] {
            "cpu/all/usage" = "255,0,0";
          })
          (monitor "memory" "Memory Usage" "org.kde.ksysguard.piechart" ["memory/physical/used"] {
            "memory/physical/used" = "255,170,0";
          })
          "org.kde.plasma.marginsseparator"
          "org.kde.plasma.systemtray"
          "org.kde.plasma.digitalclock"
          "org.kde.plasma.showdesktop"
        ];
      }
    ];
  };
}
