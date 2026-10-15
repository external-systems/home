# How the Nix flake works

You can use this repo without understanding Nix. This page is for when
you want to change how it builds.

## The files

```text
flake.nix              # inputs (outside dependencies) + the list of modules
flake.lock             # exact versions of every input (generated, commit it)
flake-parts/
├── default.nix        # formatter + MkDocs settings
├── slides.nix         # the reveal.js build and the serve-slides app
└── checks.nix         # `nix flake check`: both builds + the Nix linters
documentation/         # the MkDocs site
slides/                # the reveal.js deck
```

## Inputs and the lock file

`flake.nix` lists the **inputs**, the outside code the build uses:

| Input | What it is |
| --- | --- |
| `nixpkgs` | the Nix package collection (Python, alejandra, ...) |
| `flake-parts` | splits the flake into small modules |
| `import-tree` | loads every file in `flake-parts/` automatically |
| `mkdocs-flake` | MkDocs + Material + plugins, as a flake-parts module |
| `reveal-js` | the reveal.js source at a release tag (not a flake) |

`flake.lock` records the exact commit and content hash of each one. Commit
it: it is what makes the build reproducible.

```bash
nix flake update              # move every input to its newest version
nix flake update reveal-js    # update just one
nix flake metadata            # show what is locked
```

To move reveal.js to a new release, change the tag in its URL
(`github:hakimel/reveal.js?ref=6.0.2`) and run
`nix flake update reveal-js`.

## Why no npm?

reveal.js publishes its built files (`dist/`) inside the git repo at every
release tag. The flake fetches that tag as plain files and copies `dist/`
next to your slides, so there is no `package.json`, `node_modules` or
JavaScript build step. MkDocs is Python, and mkdocs-flake builds it from
pinned wheels.

## flake-parts and import-tree

[flake-parts](https://flake.parts) lets the flake be written as small
modules. Every `.nix` file in `flake-parts/` is one module, and
[import-tree](https://github.com/denful/import-tree) imports them all, so
adding a file there is enough to add an output (no list to update). Each
module sets options inside `perSystem`, for example `packages.slides` or
`apps.serve-slides`.

## Outputs

| Command | Output |
| --- | --- |
| `nix build .#documentation` | the docs website (from mkdocs-flake) |
| `nix build .#slides` | the slide deck |
| `nix run .#watch-documentation` | live docs preview |
| `nix run .#serve-slides` | live slides preview |
| `nix fmt .` | format `.nix` files with alejandra |
| `nix flake check` | build both sites + lint the Nix code |
| `nix develop` | a shell with the linters (alejandra, statix, deadnix) |
| `nix flake show` | list all of the above |

## Other systems

The flake builds for `x86_64-linux`. Add `"aarch64-linux"` or
`"aarch64-darwin"` to `systems` in `flake.nix` to build on ARM Linux or
Apple Silicon Macs.
