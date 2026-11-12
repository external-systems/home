# Docs settings that differ from the org defaults (pkgs flakeModules.docs,
# via org-pkgs.flakeModules.default in flake.nix). Build: nix build
# .#documentation (deck at slides/), then open result/index.html.
{
  perSystem.docs = {
    repo = "home";

    settings = {
      site_name = "Andrew's Home Monorepo";
      site_author = "Andrew Thomas Lee";

      nav = [
        {Home = "index.md";}
        {Presentation = "presentation.md";}
        {
          Architecture = [
            {Overview = "architecture/index.md";}
            {"ADR 0001 - Multi-Host Deployment" = "architecture/adr/0001-multi-host-deployment-strategy.md";}
          ];
        }
        {
          Fleet = [
            {"Machines and networking" = "fleet/index.md";}
            {"Remote builder (euc-hel-0)" = "fleet/remote-builder.md";}
            {"GitHub token rotation" = "fleet/github-token-rotation.md";}
          ];
        }
        {
          Machines = [
            {Overview = "machines/index.md";}
            {beelink = "machines/beelink.md";}
            {kamrui-h1 = "machines/kamrui-h1.md";}
            {nixos = "machines/nixos.md";}
            {ghost = "machines/ghost.md";}
            {hp-notebook = "machines/hp-notebook.md";}
            {euc-hel-0 = "machines/euc-hel-0.md";}
          ];
        }
        {"Whisper Dictation" = [{Overview = "whisper-dictation/index.md";}];}
        {
          Minecraft = [
            {Overview = "minecraft/index.md";}
            {"mc.andrewlee.fun" = "minecraft/mc-andrewlee-fun.md";}
          ];
        }
      ];

      plugins = ["search" "offline" "glightbox" "tags"];

      theme = {
        language = "en";
        favicon = "assets/brand/andrewthomaslee-transparent-logo.png";
        icon.repo = "fontawesome/brands/github";
        features = [
          "announce.dismiss"
          "content.action.edit"
          "content.action.view"
          "content.code.annotate"
          "content.code.copy"
          "content.code.select"
          "content.tabs.link"
          "content.tooltips"
          "header.autohide"
          "navigation.expand"
          "navigation.footer"
          "navigation.indexes"
          "navigation.prune"
          "navigation.sections"
          "navigation.tabs"
          "navigation.tabs.sticky"
          "navigation.top"
          "navigation.tracking"
          "search.highlight"
          "search.share"
          "search.suggest"
          "toc.follow"
          "toc.integrate"
        ];
        palette = [
          {
            media = "(prefers-color-scheme)";
            primary = "black";
            accent = "blue";
            toggle = {
              icon = "material/brightness-auto";
              name = "Switch to light mode";
            };
          }
          {
            media = "(prefers-color-scheme: light)";
            primary = "black";
            accent = "blue";
            toggle = {
              icon = "material/weather-sunny";
              name = "Switch to dark mode";
            };
          }
          {
            media = "(prefers-color-scheme: dark)";
            primary = "grey";
            accent = "blue";
            scheme = "slate";
            toggle = {
              icon = "material/weather-night";
              name = "Switch to system preference";
            };
          }
        ];
      };
    };

    slides.title = "Home Monorepo";
  };
}
