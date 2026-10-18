# Repo-local Agent Skills

Repo-local agent material, merged into every AI coding agent's skills
dir by `flake-parts/homeModules/agents.nix`
(`homeSpec.agents.skills.enabled`):

- **opencode** — `~/.config/opencode/skills`
- **pi** — `~/.agents/skills` (Agent Skills standard location)
- **kimi-code** — `~/.kimi-code/skills` (`$KIMI_CODE_HOME/skills`)
- **claude-code** — `~/.claude/skills`

The merged tree is built by `inputs.agents.lib.mkSkills`
([AGENTS](https://code.m3ta.dev/m3tam3re/AGENTS)): a `pkgs.linkFarm`
over the repo's `skills/` directory plus external flake-input skill
sources. The same tree is baked read-only at `/opt/skills` in the
OpenShell sandbox OCI image (`flake-parts/ociImages/code-agent.nix`),
so hosts and sandboxes run the identical skill set.

## Skill convention

One directory per skill, each containing a `SKILL.md` with YAML
frontmatter:

```
skills/
  my-skill/
    SKILL.md        # required: name + description frontmatter
    references/     # optional: details loaded on demand (progressive
    ...             #   disclosure keeps always-on context small)
```

```markdown
---
name: my-skill
description: "When this skill should be used (drives agent triggering)."
---
```

**Always double-quote the `description`** (escaping any embedded `\` and `"`).
pi and kimi-code parse the frontmatter with JS YAML libraries that reject a
`: ` (colon+space) inside an unquoted scalar — `description: foo: bar` fails
with "nested mappings are not allowed in compact mappings" (pi) /
"bad indentation of a mapping entry" (kimi) and the skill is **silently
skipped** (kimi logs `Skipping invalid skill`; pi reports a skill conflict).
`checks.skill-frontmatter` (`flake-parts/checks.nix`) fails `nix flake check`
on unparseable frontmatter, so CI catches it before hosts or the sandbox
image pick the skill up.

The `description` is the only trigger mechanism — write it as a
when-to-use sentence naming the phrases a user would say. Deep
"how things work" material lives in the skill body (loaded on demand
via the skill mechanism itself); keep `SKILL.md` structured with a
clear first paragraph and skim-friendly sections.

## Adding a skill — no Nix changes

1. Create `skills/<kebab-case-name>/SKILL.md` with frontmatter
   (`name`, `description`).
2. Optional: supporting files (or a `references/` subdir) inside the
   skill dir for progressive disclosure.
3. **That is the whole wiring.** `flake-parts/homeModules/agents.nix`
   merges the entire `skills/` tree via
   `inputs.agents.lib.mkSkills { customSkills = relativeToRoot "skills"; }`
   into the shared `skillsDir`, which every enabled agent's config
   symlinks. Skills are global: every machine/user with
   `homeSpec.agents.<agent>.enabled` (and thus
   `homeSpec.agents.skills.enabled`, on by default with any agent) gets
   them — there is no per-skill option. Custom skills override external
   skills on name collision.

## Adding skills from an external flake input

1. Add the source repo as a flake input in `flake.nix` (usually
   `flake = false`).
2. Add an entry to `externalSkills` in
   `flake-parts/homeModules/agents.nix` (global) or set
   `homeSpec.agents.skills.extraSources` (per machine). Each entry is
   `{src = ...;}` with optional `skillsDir` (when the repo nests its
   skills below the root) and `selectSkills` (cherry-pick by name —
   unknown names are silently dropped, so verify the installed set).
3. If the sandbox image should ship the same skills, add the source to
   `externalSkills` in `flake-parts/ociImages/code-agent.nix` too.

Among external sources, earlier entries win name collisions; custom
skills (`skills/`) always win.

## House rules

- Update this README: the Current skills list below is the
  human-facing index of this tree.
- `git add` every new file before any `nix build` / `nix flake check` —
  Nix evaluates the flake from the git tree; untracked files do not
  exist.
- Markdown alone needs no lint loop; if a `.nix` file changed, run the
  mandatory loop before declaring done: `nix fmt .` → `statix check .`
  → `deadnix --fail .`, then `nix flake check`.
- Public repo: no secrets in any file (skills, README included).
- Changes reach machines via local deploy (`nixos-rebuild --flake
  ...#<host>` / `clan machines update`), not immediately — say so if
  instant availability is expected.

## Current skills

Workflow / behavior skills:

- `baton-pass` — session handoff: saves the full state of an in-progress
  task to `.baton-pass/` (timestamped markdown file + `LATEST.md`
  pointer, auto-gitignored) so a different agent or model can resume
  where the session stopped, or resume from an existing handoff.
  Language- and repo-agnostic.

Repo knowledge skills (deep "how things work" docs, loaded on demand by
their description):

- `nix-style` — Nix code style + the mandatory alejandra/statix/deadnix
  tool loop (user preferences).
- `flakeparts` — flake-parts module system mechanics, inputs, the
  checks.lint gate, integrations.
- `import-tree` — flake-parts auto-import via import-tree: mechanics,
  tree layout, agent rules.
- `determinate` — Determinate Systems + FlakeHub: docs map, publishing,
  cache/private flakes, semver, `fh` CLI + `fh apply`.
- `home-manager` — home-manager with flakes + flake-parts, the
  homeSpec.* namespace, worked profile example.
- `clan-core` — fleet management: inventory, clanServices, vars
  generators, clan CLI, machine update flows, clanService VM tests.
- `clanservices` — authoring clan.service modules in the official
  clan-core style.
- `devenv` — devenv 2.x dev environments: CLI reference, borg hybrid
  pattern, devcontainer, containers/OCI/K8s.
- `vm-tests` — hermetic NixOS VM tests: structure, sm/md/lg tiers,
  running, agent loop.
- `github-actions` — GitHub Actions on the org's self-hosted NixOS
  runners (kamrui-h1): runner labels, preinstalled tooling, flake
  check/build/VM-test patterns, rolling-semver releases, reading failed
  logs with `gh`.
- `lib` — this repo's customLib + the AGENTS flake lib (`mkSkills`
  skill composition).
- `disko` — declarative disk partitioning: devices tree, LUKS + clan
  vars keys, redundancy recipes.
- `cilium` — Cilium 1.20.x: BGP control plane CRDs, LB IPAM, network
  policy, troubleshooting playbook.
- `rancher-kubernetes` — k3s/RKE2 operations: bootstrap, security,
  datastores, air gap, Cilium/Multus, NixOS/VM tests, k3d labs, and k3k.
- `openebs` — OpenEBS 4.6.x Kubernetes CSI storage: engines, per-node
  prerequisites, StorageClasses, upgrades, troubleshooting.
