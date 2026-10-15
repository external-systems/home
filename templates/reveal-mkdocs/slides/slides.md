# Docs & Slides with Nix

MkDocs for websites, reveal.js for talks

<small>Press <kbd>→</kbd> to start, <kbd>S</kbd> for speaker notes, <kbd>Esc</kbd> for an overview</small>

Note:
These are speaker notes. Everything after "Note:" on a slide shows up
only in the speaker view (press S). Use them for what you want to say.

---

## What this repo makes

| Folder | Becomes | Command |
| --- | --- | --- |
| `documentation/` | a docs website | `nix build .#documentation` |
| `slides/` | this slide deck | `nix build .#slides` |

Both are plain HTML + CSS + JS: host them anywhere.

---

## Getting started

```bash
nix flake init -t github:external-systems/home#reveal-mkdocs
git add .                        # Nix only sees files git knows about
nix run .#watch-documentation    # docs preview, auto-reloads
nix run .#serve-slides           # slides preview, refresh by hand
```

Open <http://127.0.0.1:8000> and start editing.

Note:
The first run downloads everything, so it takes a few minutes. After that
it starts in seconds.

---

## MkDocs in one slide

- `documentation/mkdocs.yml`: site name, sidebar (`nav:`), theme <!-- .element: class="fragment" -->
- `documentation/docs/*.md`: one Markdown file per page <!-- .element: class="fragment" -->
- New page = new `.md` file + a line in `nav:` + `git add` <!-- .element: class="fragment" -->

--

## A MkDocs page

```markdown
# My page

Some **bold** text and a [link](index.md).

!!! tip "Callout box"
    Indented text goes inside.
```

This slide sits *below* the last one (<kbd>↓</kbd>): it came from a `--` line.

---

## reveal.js in one slide

- `slides/slides.md`: the slides, in Markdown <!-- .element: class="fragment" -->
- `---` new slide right, `--` new slide down <!-- .element: class="fragment" -->
- `Note:` starts speaker notes <!-- .element: class="fragment" -->
- `slides/index.html`: theme and settings <!-- .element: class="fragment" -->

Note:
Each bullet on this slide is a "fragment": it appears on the next key
press. Add the `.element: class="fragment"` HTML comment after any line.

--

## Code that steps through

```nix [1-3|4-7]
reveal-js = {
  url = "github:hakimel/reveal.js?ref=6.0.2";
  flake = false;
};
# A release tag ships the built dist/ folder,
# so Nix just copies it next to your slides:
# zero npm, zero node_modules.
```

---

## Why Nix?

- One install: no Python, pip, Node or npm on your machine
- `flake.lock` pins every dependency: same build everywhere
- `nix flake check` builds both sites and lints the Nix code

---

## Your turn

1. Edit `slides/slides.md`, refresh the browser
2. Edit `documentation/docs/index.md`, watch it reload
3. `nix build .#documentation .#slides` and publish `result*/`

Full guide: the docs site this repo builds.
