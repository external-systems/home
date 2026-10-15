# Docs & Slides

A static documentation website ([MkDocs](https://www.mkdocs.org) +
[Material](https://squidfunk.github.io/mkdocs-material/)) and a slide deck
([reveal.js](https://revealjs.com)), both built by a Nix flake. No Python,
Node or npm to install, only Nix.

```bash
nix run .#watch-documentation   # live docs preview   → http://127.0.0.1:8000
nix run .#serve-slides          # live slides preview → http://127.0.0.1:8000

nix build .#documentation       # ./result = docs website
nix build .#slides              # ./result = slide deck
nix flake check                 # build both + lint the Nix code
```

Remember to `git add` new files: Nix only sees files git tracks.

The docs site this repo builds is also its tutorial: start with
`documentation/docs/getting-started.md`, or run the preview and read it in
the browser.

```text
flake.nix          inputs (nixpkgs, flake-parts, mkdocs-flake, reveal.js), locked in flake.lock
flake-parts/       flake modules, auto-imported: docs settings, slides build, checks
documentation/     MkDocs site: mkdocs.yml + docs/*.md
slides/            reveal.js deck: index.html + slides.md
```
