# Under the hood — what presenting actually does

Read this when debugging a build, or when changing presenting itself
(the repo dogfoods its own exports, so this is also the contributor map).
Source of truth: `lib/default.nix` and `flakeModules/slides.nix` in
`github:external-systems/presenting`.

## The reveal.js trick

reveal.js releases commit their *built* files (`dist/`: reveal.js,
reveal.css, `theme/`, `plugin/`) to the git tag. presenting pins a tag as
a `flake = false` input and copies `dist/` next to your deck as
`reveal/`. That is the whole reason there is no npm anywhere in this
stack. Upgrading reveal.js = bumping the tag in presenting's flake.nix.

## mkSlides (lib/default.nix)

One `runCommand`:

1. copy `slidesDir` to `$out`
2. `python3 inline-markdown.py $out` — every
   `<section data-markdown="x.md"></section>` in every `.html` gets its
   Markdown folded into a `<textarea data-template>`, and the `.md` files
   are deleted. Two payoffs: the built deck works from `file://` (no
   `fetch()`, which browsers block on `file://`), and no stray `.md`
   confuses MkDocs when the deck is embedded.
3. copy the reveal.js `dist/` to `$out/reveal`

`serveApp` is a `writeShellApplication` that symlinks the reveal `dist/`
plus the live files from `$PWD/<serveDirName>` into a temp dir and serves
it with `python3 -m http.server`. Live from the checkout on purpose —
edits show on refresh, no rebuild. It must run from the repo root (or
wherever `<serveDirName>` resolves); it says so and exits 1 otherwise.

## The flake-parts module (flakeModules/slides.nix)

Thin wiring over `mkSlides`:

- `packages.slides = built.package`, `apps.serve-slides = built.serveApp`
- embed: when mkdocs-flake is imported, sets
  `documentation.mkdocs-preBuildHook = "chmod u+w docs && cp -r ${config.packages.slides} docs/slides"`.
  mkdocs-flake builds in a directory where `docs/` is a symlink copy of
  your docs — read-only, hence the `chmod`. `mkdocs-preBuildHook` is
  `types.lines`, so a consumer's own hook *appends* rather than
  conflicts.
- `flake.nix` binds the module to presenting's `inputs` (the reveal.js
  pin) before exporting — consumers never reference `inputs.presenting`
  in their config.

## The mkIf trap

The embed guard is `lib.optionalAttrs (options ? documentation) (...)`,
**not** `lib.mkIf`. `mkIf` only suspends *value* evaluation — the module
system still resolves the config path `documentation.mkdocs-preBuildHook`
to a declared option, so in a flake without mkdocs-flake, `mkIf false` on
that path still dies with "The option `documentation` does not exist".
`optionalAttrs` keeps the attribute out of the config entirely. Remember
this whenever a module touches another module's options optionally.

## mkdocs-flake's options (upstream)

From `applicative-systems/mkdocs-flake`, `modules/documentation.nix`:

- `documentation.mkdocs-root` (`nullOr path`, default `null`) — no
  docs package is built until set
- `documentation.strict` (bool) — passes `--strict` to `mkdocs build`
- `documentation.mkdocs-preBuildHook` (`lines`, default `""`) — runs in
  the build dir before mkdocs
- outputs: `packages.documentation` (runCommand → `mkdocs build
  --site-dir $out`), `apps.watch-documentation` (`mkdocs serve`)

## Where things live in presenting

```text
flake.nix           inputs + let-binding that exports lib/flakeModules
lib/default.nix     mkSlides (package + serveApp)
flakeModules/slides.nix  presenting.slides.* options + wiring
flake-parts/        presenting's own site config (self-consumes the module)
flake-parts/scripts/inline-markdown.py
slides/             its own deck (also the starter-deck source)
documentation/      its own docs site (the tutorial)
```
