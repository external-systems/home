import pathlib
import re
import sys

import yaml

FRONTMATTER = re.compile(r"^---\r?\n(.*?)\r?\n---\r?\n", re.DOTALL)
ANGLE_BRACKET_MARKUP = re.compile(r"<[^>]*>")


def main():
    if len(sys.argv) != 2:
        print("Usage: check-skill-metadata.py SKILLS_DIR", file=sys.stderr)
        return 2

    root = pathlib.Path(sys.argv[1])
    skill_files = sorted(root.glob("*/SKILL.md"))
    if not skill_files:
        print(f"FAIL {root}: no skills found", file=sys.stderr)
        return 1

    failed = False
    for skill_md in skill_files:
        text = skill_md.read_text(encoding="utf-8")
        match = FRONTMATTER.match(text)
        if not match:
            print(f"FAIL {skill_md}: missing YAML frontmatter block", file=sys.stderr)
            failed = True
            continue

        try:
            meta = yaml.safe_load(match.group(1))
        except yaml.YAMLError as error:
            print(f"FAIL {skill_md}: frontmatter is not parseable YAML: {error}", file=sys.stderr)
            failed = True
            continue

        if not isinstance(meta, dict) or not all(
            isinstance(meta.get(field), str) and meta[field]
            for field in ("name", "description")
        ):
            print(
                f"FAIL {skill_md}: frontmatter must set string 'name' and 'description'",
                file=sys.stderr,
            )
            failed = True
            continue

        if meta["name"] != skill_md.parent.name:
            print(
                f"FAIL {skill_md}: name '{meta['name']}' does not match "
                f"directory '{skill_md.parent.name}'",
                file=sys.stderr,
            )
            failed = True

        fields = [
            ("name", meta["name"]),
            ("description", meta["description"]),
        ]
        if "title" in meta:
            fields.append(("title", meta["title"]))

        heading = re.search(r"^#\s+([^\r\n]+)", text[match.end() :], re.MULTILINE)
        if heading:
            fields.append(("title", heading.group(1).strip()))

        for label, value in fields:
            if not isinstance(value, str) or ANGLE_BRACKET_MARKUP.search(value):
                print(
                    f"FAIL {skill_md}: {label} contains XML-like angle-bracket markup",
                    file=sys.stderr,
                )
                failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
