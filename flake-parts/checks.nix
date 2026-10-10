{
  self,
  lib,
  ...
}: {
  perSystem = {
    pkgs,
    self',
    ...
  }: {
    # Lint gate: alejandra (format), statix (anti-patterns), deadnix (dead
    # bindings). Runs inside `nix flake check`, so CI fails on findings.
    # Source is filtered to .nix files so docs/vars changes don't
    # invalidate the check and secrets never enter this closure. Add any
    # future statix.toml to the suffix list or statix won't see it.
    checks = {
      lint =
        pkgs.runCommand "lint" {
          nativeBuildInputs = with pkgs; [alejandra statix deadnix];
        } ''
          cd ${lib.sources.sourceFilesBySuffices self [".nix"]}
          alejandra --check .
          statix check .
          deadnix --fail .
          touch $out
        '';

      # Rendered code-agent sandbox policy correctness. The TEMPLATE
      # (openshell/policies/code-agent.yaml) is placeholder-invalid
      # YAML by design; the rendered package is what the gateway
      # consumes, so this gates the rendered artifact: it must parse
      # as YAML, carry no leftover @bin_*@ placeholder, no duplicate
      # binary pins (renderSandboxConfig collapses adjacent dupes),
      # and no wildcard store binary beyond the documented
      # exceptions: kimi-code's nodejs (its closure is not this flake's
      # pkgs.nodejs; see flake-parts/openshellConfig.nix) and the go
      # toolchain (go also runs INSIDE nix builders — go-modules FODs —
      # from whatever nixpkgs the built flake pins, and nixpkgs' bin/go
      # resolves to share/go/bin/go, so both layouts are pinned; see
      # the golang entry in openshell/policies/code-agent.yaml).
      # Wildcards are gated hard: in this image the nix store is
      # agent-writable (filesystem policy marks /nix read_write), so
      # a wildcard binary pin is an egress forge vector — mint a
      # matching store path and inherit its hosts. The exact-pin
      # default is enforced here.
      #
      # Also gated: every allow-rule PATH in the policy AND in the
      # rendered github-agent profile. OpenShell matches rule paths as
      # globs (openshell-core endpoint_path.rs), so a typo like
      # "/>/git-upload-pack" ('>' is a glob LITERAL, not a separator)
      # compiles fine but matches no real request — the rule goes dead
      # while everything still works in provider-attached sandboxes,
      # which carry their own git-transport rules. The gate: a rule
      # path is "**" or starts with "/" and uses only RFC3986 pchar
      # characters plus glob metacharacters (* ? [ ] { }) — anything
      # else (">", "<", space, quotes, '#') is invalid in a URL
      # path and therefore always a typo.
      code-agent-policy =
        pkgs.runCommand "check-code-agent-policy" {
          nativeBuildInputs = [pkgs.gawk pkgs.gnugrep pkgs.python3 pkgs.yq-go];
          policy = self'.packages.code-agent-policy;
          profile = self'.packages.github-agent-profile;
        } ''
          # Parses as YAML, placeholder-free.
          yq -e . "$policy" >/dev/null
          if grep -qE '@bin_[a-z0-9_]+@' "$policy"; then
            echo "FAIL: leftover @bin_*@ placeholder in the rendered policy" >&2
            exit 1
          fi

          # No duplicate binary pins WITHIN one policy entry — a dup
          # means a render regression (the dedupe in renderSandboxConfig
          # stopped collapsing adjacent identical entries). The same
          # binary pinned by DIFFERENT entries is legitimate (bin_nix
          # appears in most of them).
          dupes="$(yq -r '.network_policies | to_entries[] | .key as $k | ((.value.binaries // [])[] | .path) | "\($k) \(.)"' "$policy" | sort | uniq -d || true)"
          if [ -n "$dupes" ]; then
            echo "FAIL: duplicate binary pins in the rendered policy:" >&2
            echo "$dupes" >&2
            exit 1
          fi

          # Only the sanctioned wildcard binary pins (see above).
          wildcards="$(grep -oE 'path: /nix/store/\*[^ }]+' "$policy" | sort -u || true)"
          expected="$(printf '%s\n' \
            'path: /nix/store/*-go-*/bin/go' \
            'path: /nix/store/*-go-*/share/go/bin/go' \
            'path: /nix/store/*-nodejs*/bin/node')"
          if [ "$wildcards" != "$expected" ]; then
            echo "FAIL: unexpected wildcard binary pins (sanctioned: the kimi nodejs entry and the two go toolchain layouts):" >&2
            echo "$wildcards" >&2
            exit 1
          fi

          # Allow-rule path sanity for BOTH rendered configs (see the
          # header comment): walk every rules[].allow.path and reject
          # characters that can never appear in a URL path.
          for rendered in "$policy" "$profile"; do
            yq -o=json . "$rendered" | python3 ${pkgs.writeText "check-rule-paths.py" ''
            import json
            import re
            import sys

            # "**", or an absolute path of RFC3986 pchar characters
            # (unreserved / sub-delims / ':' / '@') plus '/' and the
            # glob metacharacters OpenShell honors (* ? [ ] { }).
            ALLOWED = re.compile(r"^(\*\*|/[A-Za-z0-9._~!$&'()*+,;=:@/?*{}\[\]-]*)$")

            def rule_paths(node, trail):
                if isinstance(node, dict):
                    for key, value in node.items():
                        if key == "allow" and isinstance(value, dict) and "path" in value:
                            yield ".".join(trail), value["path"]
                        else:
                            yield from rule_paths(value, trail + [str(key)])
                elif isinstance(node, list):
                    for index, item in enumerate(node):
                        yield from rule_paths(item, trail + [str(index)])

            doc = json.load(sys.stdin)
            failed = False
            for where, path in rule_paths(doc, []):
                if not isinstance(path, str) or not ALLOWED.match(path):
                    print(
                        f"FAIL: rule path {path!r} at {where} is not '**' or an "
                        "absolute path of URL-path + glob characters",
                        file=sys.stderr,
                    )
                    failed = True
            sys.exit(1 if failed else 0)
          ''} || exit 1
          done
          touch $out
        '';

      # devenv lock drift: devenv.yaml/devenv.lock pin nixpkgs, nixpkgs-unstable
      # and clan-core to the exact revisions flake.lock holds, so both
      # lockfiles reference identical sources (same builds, shared
      # devenv.cachix.org cache). Fails when flake.lock was bumped without
      # bumping the devenv pins (or vice versa) — update both in one commit
      # (`nix flake update <input>` + edit devenv.yaml + `devenv update`).
      devenv-lock-drift =
        pkgs.runCommand "devenv-lock-drift"
        {
          nativeBuildInputs = [pkgs.jq];
          flakeLock = "${self}/flake.lock";
          devenvLock = "${self}/devenv.lock";
        }
        ''
          status=0
          for input in nixpkgs nixpkgs-unstable clan-core nix2container mk-shell-bin; do
            flake_rev=$(jq -r ".nodes.\"$input\".locked.rev // empty" "$flakeLock")
            devenv_rev=$(jq -r ".nodes.\"$input\".locked.rev // empty" "$devenvLock")
            if [ -z "$flake_rev" ]; then
              echo "FAIL: flake.lock has no locked rev for $input" >&2
              status=1
            elif [ "$flake_rev" != "$devenv_rev" ]; then
              echo "FAIL: $input drifted: flake.lock=$flake_rev devenv.lock=$devenv_rev" >&2
              echo "      Update devenv.yaml pins + devenv update in the same commit." >&2
              status=1
            fi
          done
          if [ "$status" -ne 0 ]; then exit 1; fi
          touch $out
        '';

      # Skill frontmatter gate: pi and kimi-code parse SKILL.md frontmatter
      # with JS YAML libraries that reject ': ' (colon+space) inside an
      # unquoted plain scalar and then SILENTLY skip the skill (pi reports
      # a skill conflict, kimi logs "Skipping invalid skill"). PyYAML
      # enforces the same restriction, so this fails `nix flake check`
      # before a broken skill reaches hosts or the code-agent image.
      skill-frontmatter =
        pkgs.runCommand "skill-frontmatter"
        {
          nativeBuildInputs = [
            (pkgs.python3.withPackages (ps: [ps.pyyaml]))
          ];
        }
        ''
          python3 ${pkgs.writeText "check-skill-frontmatter.py" ''
            import pathlib
            import re
            import sys

            import yaml

            root = pathlib.Path(sys.argv[1])
            failed = False
            for skill_md in sorted(root.glob("*/SKILL.md")):
              text = skill_md.read_text(encoding="utf-8")
              match = re.match(r"^---\r?\n(.*?)\r?\n---\r?\n", text, re.DOTALL)
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
              if not isinstance(meta, dict) or not meta.get("name") or not meta.get("description"):
                print(f"FAIL {skill_md}: frontmatter must set 'name' and 'description'", file=sys.stderr)
                failed = True
                continue
              if meta["name"] != skill_md.parent.name:
                print(
                  f"FAIL {skill_md}: name '{meta['name']}' does not match "
                  f"directory '{skill_md.parent.name}'",
                  file=sys.stderr,
                )
                failed = True
            sys.exit(1 if failed else 0)
          ''} ${self}/skills
          touch $out
        '';
    };
  };
}
