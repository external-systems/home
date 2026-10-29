---
name: terranix
description: "Terranix with Nix flakes: generate Terraform JSON from Nix modules, wire flake-parts configurations, use OpenTofu or Terraform, consume HCL modules, configure Hetzner/AWS/GCP/Azure/Cloudflare/Proxmox providers, manage path-style S3 backends, and debug evaluation/state/applies. Load whenever the user mentions terranix, .tf.json generation in Nix, Terraform/OpenTofu in a flake, or maintaining infrastructure as Nix attrsets."
---

# terranix

[Terranix](https://github.com/terranix/terranix) evaluates NixOS-style modules
into Terraform JSON. Terraform or OpenTofu then owns provider validation,
planning, state, and API operations. The two evaluation phases are separate:
Nix errors happen while generating JSON; provider and backend errors happen in
the runtime.

This skill assumes flakes. It was researched against terranix main at
[`b6c05a4`](https://github.com/terranix/terranix/tree/b6c05a45b2435cb3471d6f135ddb0b3c2934cc45)
with the 2.9.0 release compared explicitly. Check the consumer's `flake.lock`
before using post-release features. Current main needs a 25.05-era or newer
nixpkgs; use the 2.9.0 tag when an older package set cannot be bumped.

## Route the task

| Branch | Read |
|---|---|
| Add terranix to a flake, use flake-parts, OpenTofu, wrappers, or multiple environments | [references/flake-parts.md](references/flake-parts.md) |
| Author Nix modules, escape references, consume external HCL modules, or use lifecycle blocks | [references/modules.md](references/modules.md) |
| Configure Hetzner, AWS, GCP, Azure, Cloudflare, or Proxmox | [references/providers.md](references/providers.md) |
| Configure state, Hetzner path-style S3, upgrade pins, debug, plan, import, or destroy | [references/state-and-operations.md](references/state-and-operations.md) |

Read only the relevant reference, plus the provider's official documentation
for resource schemas. For broader Terraform/OpenTofu policy, testing, and state
practices, also use the `terraform-skill` when available.

## Start with flake-parts and OpenTofu

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    terranix = {
      url = "github:terranix/terranix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [inputs.terranix.flakeModule];
      systems = ["x86_64-linux"];
      perSystem = {pkgs, ...}: {
        terranix.terranixConfigurations.infra = {
          terraformWrapper.package = pkgs.opentofu;
          modules = [./config.nix];
        };
      };
    };
}
```

Use `inputs.terranix.flakeModule`, not `flakeModules.default`: the latter is an
error in one upstream documentation example and is absent at the researched
revision. `terraformWrapper.package` chooses the executable; the wrapper uses
its `meta.mainProgram`, so OpenTofu scripts invoke `tofu`.

For a configuration named `infra`:

```sh
nix run .#infra.init
nix run .#infra.plan
nix develop .#infra
```

Any configuration name gets `packages.<name>` and passthru scripts. At the
researched revision, avoid the literal name `default`: its additional top-level
`apps` entries lack the required app schema and make `nix flake check` fail.
Use another name and the passthru commands above until upstream fixes that
output. Re-enter a devShell after configuration edits because its scripts
retain the previous generation's store paths.

## Write Terraform-shaped Nix

```nix
{lib, ...}: {
  terraform = {
    required_version = ">= 1.6";
    required_providers.local = {
      source = "hashicorp/local";
      version = "~> 2.5";
    };
  };

  resource.local_file.example = {
    filename = "./example.txt";
    content = "hello\n";
  };

  output.example_content.value = lib.tf.ref "local_file.example.content";
}
```

Resource and provider arguments keep the names and nesting from Terraform JSON.
Nix attrsets replace HCL blocks; lists represent repeated blocks where the
provider schema expects them. Use `lib.tf.ref` or escaped strings for references
that Terraform must resolve at plan/apply. Reading through `config.resource`
without calling the block returns a Nix value instead.

Terranix has no provider schema knowledge. A successful Nix build proves JSON
generation, not provider validity or API access; run init, validate, and plan.

## Keep the change safe and verifiable

1. **Capture the execution context.** Record Terraform/OpenTofu and provider
   versions, terranix revision, backend, execution path, state owner, and
   environment criticality. Set `terraform.required_version` and provider
   constraints from facts rather than assuming the newest feature exists.
2. **Choose the reuse layer.** Use Nix modules for programmatic composition;
   use `module.<name>.source` for existing HCL modules. Relative HCL module
   paths resolve from the runtime workdir.
3. **Keep credentials at runtime.** Literal secrets in Nix or generated JSON
   enter the world-readable store. Export provider environment variables or
   `TF_VAR_*` values through `terraformWrapper.prefixText`; declare sensitive
   variables without defaults. State, plans, backend metadata, and debug logs
   can still contain secrets.
4. **Preserve ownership history.** Use `moved`, `import`, and `removed` blocks
   with their runtime floors. Back up state before migration, and never delete
   state to resolve an apply error.
5. **Verify in phases.** Build/inspect JSON, initialize, validate, then save and
   review a plan. Apply that exact plan artifact after approval. For destroy,
   review `plan -destroy` output and obtain explicit confirmation; avoid
   `-auto-approve`.
6. **Report operations precisely.** State assumptions and version floors, the
   risks addressed, chosen remediation and tradeoffs, exact validation commands,
   and rollback notes for state-mutating or destructive work.

The generated `nix run .#<name>` app runs init followed by apply directly. Use
the wrapped runtime from `nix develop .#<name>` for a reviewed production plan
artifact rather than making that app the production approval path.

## Debug in the failing phase

- **Nix evaluation:** inspect the option path, unescaped `${...}`, merge type
  conflicts, and failed assertions. Use `lib.evalTerranixConfiguration` in
  `nix repl` or build `.#<name>.config` and inspect the JSON with `jq`.
- **Initialization:** check runtime/provider versions, `required_providers`,
  backend literals, credentials, network access, and the committed
  `.terraform.lock.hcl`.
- **Validation:** compare generated arguments with the locked provider's docs.
  Azure's empty `features = {};` and Cloudflare's v5 resource names are common
  schema issues, not Nix problems.
- **Plan/apply:** check authentication, API permissions, live drift, state
  ownership, and locks. Use `tofu show`, `tofu state list`, and `tofu output`
  read-only before considering state changes.
- **Stale behavior:** confirm the selected workdir and re-enter the devShell.
  The scripts create the workdir and symlink `config.tf.json` themselves.

Use `TF_LOG=DEBUG`/`TRACE` only for focused reproduction because provider logs
may expose credentials or sensitive API data.

## Maintain from primary sources

Update the terranix input and provider pins in separate, reviewable changes.
Read the [changelog](https://github.com/terranix/terranix/blob/main/Changelog.md)
and provider upgrade guides, regenerate the lockfile deliberately, and compare
plans. Prefer terranix.org and the upstream tests over the archived
`terranix-examples` repository. Replace deprecated `terranixConfigurationAst`,
`buildTerranix`, and `buildOptions` before 3.0.0.

Primary sources: [core](https://github.com/terranix/terranix/tree/b6c05a45b2435cb3471d6f135ddb0b3c2934cc45/core),
[flake library](https://github.com/terranix/terranix/blob/b6c05a45b2435cb3471d6f135ddb0b3c2934cc45/flake/lib.nix),
[flake-parts module](https://github.com/terranix/terranix/blob/b6c05a45b2435cb3471d6f135ddb0b3c2934cc45/flake-module.nix),
[tests](https://github.com/terranix/terranix/tree/b6c05a45b2435cb3471d6f135ddb0b3c2934cc45/tests),
[maintained documentation](https://terranix.org/docs/), and
[OpenTofu backend documentation](https://opentofu.org/docs/language/settings/backends/).
