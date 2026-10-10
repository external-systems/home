# Agent Skills — Declarative Skill Management

Agent skills are packaged instructions (`SKILL.md` + optional supporting
files) that extend agent capabilities. This flake manages them
declaratively for **all four coding agents** from one module,
`flake-parts/homeModules/agents.nix`, under the `homeSpec.agents`
namespace:

| Option | What enabling it does |
|---|---|
| `homeSpec.agents.skills.enabled` | Build the shared skills tree and wire it into every enabled agent's skills dir. Defaults to true when any agent is enabled. |
| `homeSpec.agents.opencode.enabled` | opencode + the shared tree at `~/.config/opencode/skills` |
| `homeSpec.agents.pi.enabled` | pi + the shared tree at `~/.agents/skills` (Agent Skills standard location) |
| `homeSpec.agents.kimi.enabled` | kimi-code + the shared tree at `~/.kimi-code/skills` (`$KIMI_CODE_HOME/skills`) |
| `homeSpec.agents.claude.enabled` | claude-code + the shared tree at `~/.claude/skills` |

The dev profile (`flake-parts/homeModules/profiles/netsa.nix`) enables
skills plus all four agents.

## Composition

Merging is done by `inputs.agents.lib.mkSkills`
([AGENTS](https://code.m3ta.dev/m3tam3re/AGENTS)), which builds a
`pkgs.linkFarm` — one symlink per skill directory — from the repo's
`skills/` tree plus external flake-input skill sources:

```nix
skillsDir = inputs.agents.lib.mkSkills {
  inherit pkgs;
  customSkills = relativeToRoot "skills";
  externalSkills = [
    {src = inputs.skills-anthropic;}   # anthropics/skills, skills/ dir
  ] ++ cfg.skills.extraSources;
};
```

The same helper builds the tree baked at `/opt/skills` in the OpenShell
sandbox image, so hosts and sandboxes run the identical skill set (see
the [Code-Agent Image](../openshell/code-agent-image.md)).

### Sources

| Source | Type | Skills |
|---|---|---|
| `skills/` (this repo) | custom | `baton-pass` plus the repo-knowledge skills (`nix-style`, `flakeparts`, `import-tree`, `determinate`, `home-manager`, `clan-core`, `clanservices`, `devenv`, `vm-tests`, `lib`, `disko`, `cilium`, `openebs`) — the former attachable reference bundles, migrated to skills |

External sources are flake inputs (usually `flake = false`); `mkSkills`
reads each repo's `skills/` directory (override with `skillsDir`,
cherry-pick with `selectSkills = [...]`).

### Precedence

1. Custom skills (`skills/`) override same-named externals.
2. Among externals, earlier entries in `externalSkills` win.

## Adding a custom skill

One directory per skill under `skills/`, containing a `SKILL.md` with YAML
frontmatter (`name`, `description` — the description drives agent triggering):

```
skills/
  my-skill/
    SKILL.md
    references/   # optional supporting files
```

Then `git add skills/my-skill/` — Nix evaluates the flake from the git tree,
so untracked files are invisible to `nix build` / `nix flake check`.

No Nix changes are needed: the `mkSkills` call merges the whole `skills/`
tree automatically. Custom skills are global (no per-profile opt-in) and
override same-named external skills. Keep `skills/README.md`'s skill list
in sync.

## Adding an external source

Add a `flake = false` input in `flake.nix`, then either append to
`externalSkills` in `flake-parts/homeModules/agents.nix` (fleet-wide) or
set the per-machine option:

```nix
# flake.nix
skills-acme = {
  url = "github:acme/skills";
  flake = false;
};
```

```nix
# per machine / profile
homeSpec.agents.skills.extraSources = [
  {src = inputs.skills-acme;}
];
```

If the sandbox image should ship the same skills, add the source to
`externalSkills` in `flake-parts/ociImages/code-agent.nix` too.

## Verify

- Eval + symlink path:
  `nix eval --raw .#nixosConfigurations.<name>.config.home-manager.users.netsa.home.file.\".agents/skills\".source`
  — prints the `mkSkills` store path; `ls` it to see the merged skill set
  (opencode's copy is `xdg.configFile.\"opencode/skills\".source`).
- `nix flake check --show-trace` evaluates all machines (CI parity).
- Build a machine toplevel to exercise the module end-to-end:
  `nix build .#nixosConfigurations.ghost.config.system.build.toplevel`
