# Getting started

## 1. Install Nix

Nix is the only tool you install. Everything else (Python, MkDocs,
reveal.js) comes from the flake.

=== "Linux / macOS / WSL"

    Use the [Determinate Nix installer](https://docs.determinate.systems/),
    which turns on flakes for you:

    ```bash
    curl -fsSL https://install.determinate.systems/nix | sh -s -- install
    ```

=== "NixOS"

    Turn on flakes in your configuration:

    ```nix
    nix.settings.experimental-features = ["nix-command" "flakes"];
    ```

Check it works with `nix --version`.

## 2. Create your repo from this template

```bash
mkdir my-site && cd my-site
git init
nix flake init -t github:external-systems/home#reveal-mkdocs
git add .
```

!!! warning "Always `git add` new files"
    Inside a git repo, Nix only sees files git knows about. A new page that
    is not `git add`-ed is invisible to `nix build`, and the build fails
    with a "file not found" error. You do not need to commit, only add.

## 3. Preview while you edit

Each command starts a small web server. Leave it running, edit files, and
refresh the browser.

```bash
nix run .#watch-documentation   # docs   → http://127.0.0.1:8000 (auto-reloads)
nix run .#serve-slides          # slides → http://127.0.0.1:8000 (refresh by hand)
```

Both use port 8000, so run one at a time, or give the slides another
port: `nix run .#serve-slides -- 8001`.

The first run downloads and builds the tools, which takes a few minutes.
Later runs start in seconds.

## 4. Build the final sites

```bash
nix build .#documentation   # ./result = the docs website
nix build .#slides          # ./result = the slide deck
```

`result` is a read-only link into the Nix store. To publish, copy its
contents somewhere: `cp -rL result/. public/`. Build both at once with
separate links:

```bash
nix build .#documentation .#slides
# → ./result (docs) and ./result-1 (slides)
```

## 5. Check everything before you push

```bash
nix fmt .           # format the .nix files
nix flake check     # builds both sites and lints the Nix code
```

## 6. Publish (example: GitHub Pages)

Any host that serves a folder works. For GitHub Pages, a workflow can run
`nix build .#documentation`, copy `result/` and upload it with
[`actions/upload-pages-artifact`](https://github.com/actions/upload-pages-artifact).
Put the slides in a subfolder of the same upload if you want both on one
site, for example `cp -rL result-1/. public/slides/`.
