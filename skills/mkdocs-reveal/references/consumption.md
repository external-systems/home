# Consuming presenting — annotated reference

Every file a consumer touches, end to end. The example assumes a
flake-parts repo; without flake-parts, skip to the `lib.mkSlides` section
at the bottom.

## flake.nix

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    presenting = {
      url = "github:external-systems/presenting";
      # Dedupe onto this flake's pins — smaller closure, one upgrade path.
      # Nested form: 3+ flat `inputs.<x>.follows` lines trip statix W20.
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];
      imports = [
        # Docs AND slides, one import (mkdocs-flake comes along):
        inputs.presenting.flakeModules.default

        # — OR, when this flake already imports mkdocs-flake itself:
        # inputs.presenting.flakeModules.slides
        # Importing both shapes declares mkdocs-flake's options twice.
      ];

      perSystem = {...}: {
        presenting.slides.dir = ./slides;
        documentation.mkdocs-root = ./documentation;
        # documentation.strict = true;  # broken links fail the build
      };
    };
}
```

Config, in full (all under `presenting.slides.*`):

| Option | Default | Meaning |
| --- | --- | --- |
| `enable` | `true` | build the deck at all |
| `dir` | — (required) | deck directory: `index.html` + markdown |
| `serveDirName` | `"slides"` | where `serve-slides` finds live files, from the CWD it is run in |
| `embedInDocs` | `true` iff mkdocs-flake is imported | copy the deck into the site at `/slides/` |

## The deck directory

Copy `starter-deck/` (next to this file) as `slides/`, edit the title in
`index.html` and the slides in `slides.md`. Multiple decks in one
directory work: each gets its own `.html` with a
`<section data-markdown="that-deck.md">`.

## Linking the deck from the docs

`documentation/docs/presentation.md` — note the plain-HTML links, which
is what keeps strict builds and the live preview working (Markdown links
are validated against `docs/`, where the deck only exists mid-build):

```markdown
# Presentation

<a href="../slides/index.html" target="_blank">Open the deck</a>

<iframe src="../slides/index.html" title="Slide deck"
  style="width: 100%; aspect-ratio: 16 / 9; border: 0;"
  allowfullscreen></iframe>
```

The URLs are relative to the page's built URL (`/presentation/`), so
`../slides/` lands on `/slides/`. Add the page to `nav` in `mkdocs.yml`:

```yaml
nav:
  - Home: index.md
  - Presentation: presentation.md
```

## GitHub Pages

Presenting's own `.github/workflows/pages.yml` is the reference: `nix
flake check`, `nix build .#documentation`, `cp -rL result _site` (the
store is read-only, hence the copy), `upload-pages-artifact` +
`deploy-pages`. Copy it unchanged; the only per-repo setup is Settings →
Pages → Source: GitHub Actions.

## Without flake-parts: lib.mkSlides

`inputs.presenting.lib.mkSlides` is the module's engine, usable from any
flake shape:

```nix
packages.x86_64-linux.slides = let
  pkgs = import inputs.nixpkgs {system = "x86_64-linux";};
  built = inputs.presenting.lib.mkSlides {
    inherit pkgs;
    slidesDir = ./slides;
    # serveDirName = "slides";        # default
    # revealSrc = "${someOtherReveal}/dist";  # override the reveal.js pin
  };
in
  built.package;

# built.serveApp is the ready-made `apps` entry for live preview.
```
