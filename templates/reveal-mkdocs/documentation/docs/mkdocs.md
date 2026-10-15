# MkDocs basics

[MkDocs](https://www.mkdocs.org) turns a folder of Markdown files into a
website with a sidebar, search and page-to-page links. This repo uses the
[Material](https://squidfunk.github.io/mkdocs-material/) theme on top.

## The two things you edit

```text
documentation/
├── mkdocs.yml      # site settings: name, sidebar (nav), theme, extensions
└── docs/           # one Markdown file per page
    ├── index.md    # the home page (URL: /)
    └── mkdocs.md   # this page   (URL: /mkdocs/)
```

## Add a page

1. Create `documentation/docs/my-page.md`:

    ```markdown
    # My page

    Some text with **bold**, *italic* and a [link](index.md).
    ```

2. Add it to `nav:` in `mkdocs.yml`:

    ```yaml
    nav:
      - Home: index.md
      - My page: my-page.md
    ```

3. `git add documentation/docs/my-page.md` so Nix can see it.

Subfolders become sections: `docs/guides/setup.md` is linked as
`guides/setup.md`, and nav entries can nest:

```yaml
nav:
  - Guides:
      - Setup: guides/setup.md
```

## Markdown cheat sheet

````markdown
# Page title (one per page)
## Section        ### Subsection

**bold**  *italic*  `inline code`  [link text](other-page.md)

- bullet list
1. numbered list

| Table | Header |
| ----- | ------ |
| cell  | cell   |

![Alt text](images/picture.png)

```python
print("code block with syntax highlighting")
```
````

Link to other pages by their **file path** (`other-page.md`), not their
URL. MkDocs rewrites the links and, because this repo builds with
`strict: true`, fails the build when one points at a missing page.

## Material extras used here

!!! note "Admonitions"
    Callout boxes: `!!! note`, `!!! tip`, `!!! warning`, `!!! danger`,
    followed by an indented body. Use `???` instead of `!!!` for a box
    that starts collapsed.

```markdown
!!! tip "Optional title"
    Indented text inside the box.
```

Tabs group alternatives:

```markdown
=== "Linux"
    Text for Linux.

=== "macOS"
    Text for macOS.
```

Each feature is switched on by a line under `markdown_extensions:` in
`mkdocs.yml`. The [Material reference](https://squidfunk.github.io/mkdocs-material/reference/)
lists many more (diagrams, footnotes, icons) and the line each one needs.

## Images and other files

Anything in `docs/` that is not Markdown (images, PDFs, CSS) is copied to
the site as-is. Put pictures in `docs/images/` and link them with
`![description](images/name.png)`.

## Which plugins can I use?

The site is built by [mkdocs-flake](https://github.com/applicative-systems/mkdocs-flake),
which bundles MkDocs, Material and a set of popular plugins (search,
glightbox, mermaid2, redirects, awesome-pages, and others). Add any of them
under `plugins:` in `mkdocs.yml`. A plugin outside that set needs a custom
`documentation.mkdocs-package` in `flake-parts/default.nix`.
