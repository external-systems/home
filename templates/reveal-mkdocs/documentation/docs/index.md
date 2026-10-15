# Welcome

This repository builds **two static websites** from plain text files:

| What | Source | Built with | Build command |
| --- | --- | --- | --- |
| This documentation site | `documentation/` | [MkDocs](https://www.mkdocs.org) + [Material](https://squidfunk.github.io/mkdocs-material/) | `nix build .#documentation` |
| A slide deck | `slides/` | [reveal.js](https://revealjs.com) | `nix build .#slides` |

Both builds produce a folder of HTML, CSS and JavaScript (`./result`) that
any static host can serve: GitHub Pages, Cloudflare Pages, Netlify, an S3
bucket, or `python3 -m http.server`.

[Nix](https://nixos.org) builds everything. It downloads the exact versions
recorded in `flake.lock`, so the site builds the same on every machine and
you never install Python packages or run `npm`.

## Where to go next

1. **[Getting started](getting-started.md)**: install Nix, build both
   sites, and preview them while you edit.
2. **[MkDocs basics](mkdocs.md)**: how pages, the sidebar and Markdown work.
3. **[reveal.js basics](reveal-js.md)**: how to write slides.
4. **[How the Nix flake works](nix.md)**: what each file in the repo does,
   and how to update or extend it.

!!! tip "The slides teach the same thing"
    Run `nix run .#serve-slides` and open <http://127.0.0.1:8000> for a
    short deck on MkDocs, reveal.js and this repo. Press ++s++ for its
    speaker notes.
