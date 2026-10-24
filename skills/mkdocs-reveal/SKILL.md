---
name: mkdocs-reveal
description: "Add a MkDocs documentation site and a reveal.js slide deck to a Nix flake repo as build artifacts (packages.documentation, packages.slides, live-preview apps, GitHub Pages deploy) by consuming the external-systems/presenting flake — its flakeModules and lib.mkSlides carry the reveal.js pin and all build logic, so the consumer writes a few lines, no boilerplate. Also covers scaffolding a greenfield docs+slides repo from the presenting template. Load this whenever the user mentions MkDocs, reveal.js, slides, slide decks, presentations, docs sites, or GitHub Pages in a Nix/flake context, wants markdown turned into a website or deck, or asks to document a flake repo — even if they never name the presenting flake."
---

# MkDocs + reveal.js in a flake

Two build artifacts from plain Markdown, built by Nix with zero npm and
zero Python installs: a MkDocs (Material) website and a reveal.js slide
deck, optionally embedded in the site at `/slides/`. All of the build
machinery lives in the `external-systems/presenting` flake and rides into
a consumer as a flake input — the consumer's job is a few lines of config,
never copied build code.

## Pick the path

- **Existing flake** → consume `presenting` as an input (the rest of this
  file). This is the common case.
- **Greenfield repo that is only docs + slides** →
  `nix flake init -t github:external-systems/presenting`, then `git add .`.
  The template's own docs site is the tutorial; you're done here.
- **Debugging the build, or changing presenting itself** → read
  `references/under-the-hood.md` for what the module does mechanically.

## Consume from an existing flake

Three edits. Full annotated versions of every snippet are in
`references/consumption.md`.

**1. Add the input** (flake.nix):

```nix
inputs.presenting = {
  url = "github:external-systems/presenting";
  # Nested `inputs = {...}` on purpose: three or more flat
  # `inputs.<x>.follows` lines trip statix's repeated-keys lint (W20).
  inputs = {
    nixpkgs.follows = "nixpkgs";
    flake-parts.follows = "flake-parts";
    mkdocs-flake.follows = "mkdocs-flake";  # only if you already have it
  };
};
```

The `follows` lines deduplicate the dependency graph onto the consumer's
own pins. reveal.js itself needs no input and no follows — its pin
travels inside presenting, which is the point: one place upgrades it.

**2. Import one module** (flake-parts `imports`) — the choice matters:

- Already importing `mkdocs-flake.flakeModules.default` yourself →
  `inputs.presenting.flakeModules.slides`
- No mkdocs-flake import anywhere → `inputs.presenting.flakeModules.default`
  (pulls mkdocs-flake in for you)

Importing `flakeModules.default` *and* mkdocs-flake yourself declares
mkdocs-flake's options twice and fails eval. Pick exactly one shape.

**3. Point it at the deck** (any perSystem module):

```nix
presenting.slides.dir = ./slides;
# only when the deck is not at <repo-root>/slides — the serve app looks
# for the live files by this name from wherever you run it:
presenting.slides.serveDirName = "documentation/slides";
```

**Then `git add` every new file.** Nix evaluates the flake from the git
tree; untracked files don't exist and the failure ("file not found")
never mentions git. This is the single most common trip-wire.

You now have:

| Command | Result |
| --- | --- |
| `nix build .#documentation` | the website, deck embedded at `/slides/` |
| `nix build .#slides` | just the deck (opens from `file://`) |
| `nix run .#watch-documentation` | live docs preview, `127.0.0.1:8000` |
| `nix run .#serve-slides [-- 8001]` | live slides preview, serves the checkout |
| `nix flake show` | confirm the outputs exist |

The embed is automatic: when mkdocs-flake is imported, `embedInDocs`
defaults on and the built deck is copied into the site before MkDocs
runs. `presenting.slides.embedInDocs = false;` opts out.

## The deck

A deck directory is `index.html` + one Markdown file per
`data-markdown` deck. Start from `references/starter-deck/` (copy both
files, edit the title and slides). Markdown separators, matched against
whole lines:

- `---` — next slide to the right
- `--` — next slide below
- `Note:` — speaker notes to the end of the slide

Swap the theme by editing the `reveal/theme/black.css` link in
`index.html` (`white`, `league`, `moon`, `dracula`, ... — see
`reveal/theme/` in the built output). Live-edit loop: run
`nix run .#serve-slides` from the repo root, edit the `.md`, refresh.
Both preview apps default to port 8000; pass another port to run both.

## The docs site

Point mkdocs-flake at the directory holding `mkdocs.yml`:

```nix
documentation.mkdocs-root = ./documentation;
documentation.strict = true;   # broken links fail the build
```

When linking to the embedded deck from a docs page, use plain HTML, not
Markdown links: MkDocs validates Markdown links against `docs/`, where
`/slides/` only exists during the build, so a strict build fails and the
live preview 404s. The iframe embed page in
`references/consumption.md` shows the pattern — steal it verbatim.

## Upgrading and overriding

- New reveal.js or build fixes: `nix flake update presenting`.
- Pin reveal.js differently for one consumer, or build something the
  module doesn't offer: call the builder directly —
  `inputs.presenting.lib.mkSlides { inherit pkgs; slidesDir = ./slides; revealSrc = ...; }`
  returns `{ package, serveApp; }` (see `references/under-the-hood.md`).

## What not to do

Never commit build artifacts: no `result` links, no `_site/` or `site/`,
no built deck or site copied into the tree, no `gh-pages` pushes. The
site and deck are built in CI and deployed to GitHub Pages only
(presenting's `pages.yml`). Gitignore `result`, `result-*`, `site/`,
`_site/` and `documentation/site/` in every consumer, and say so in its
CLAUDE.md.

Copying presenting's `flake-parts/slides.nix`, `inline-markdown.py`, or
the reveal-js input pin into a consumer is the old template-era pattern —
it forks code that now has a maintained upstream. If you find yourself
transcribing build logic, import the module or call `lib.mkSlides`
instead; if neither fits, the right fix is a presenting PR, and
`references/under-the-hood.md` is the map.
