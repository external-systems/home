# Flake-parts configurations

Use terranix's flake module when a flake should own the generated configuration,
runtime scripts, and development shell. It evaluates the same Nix modules as
`terranix.lib.terranixConfiguration` but also wires the flake outputs.

## Minimal OpenTofu setup

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
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

Run `nix flake lock` after adding the inputs. Following the consumer's nixpkgs
keeps the runtime and provider packages on the consumer's package set. Import
`inputs.terranix.flakeModule`; the `flakeModules.default` spelling shown on one
upstream documentation page is not an output at the researched revision.

A minimal `config.nix` needs no provider-specific Nix library:

```nix
{
  terraform.required_providers.local = {
    source = "hashicorp/local";
    version = "~> 2.5";
  };

  resource.local_file.example = {
    filename = "./example.txt";
    content = "hello from terranix\n";
  };
}
```

## Generated interfaces

For `terranix.terranixConfigurations.<name>`:

| Command or output | Result |
|---|---|
| `nix run .#<name>` | Run init and apply |
| `nix run .#<name>.init` | Initialize providers and backend |
| `nix run .#<name>.plan` | Run init and plan |
| `nix run .#<name>.destroy` | Run init and destroy |
| `nix develop .#<name>` | Enter a shell with `init`, `apply`, `plan`, `destroy`, and the wrapped runtime |
| `nix build .#<name>.config` | Build only the generated Terraform JSON |
| `.#packages.<system>.<name>` | The apply package carrying the other scripts as passthru attributes |

The nested command names are passthru attributes on the apply derivation; they
are not nested flake `apps`. At the researched revision, a configuration named
`default` also emits top-level `apps`, but those entries lack the required app
schema and make `nix flake check` fail. Avoid `default` until upstream fixes
that output; use another configuration name and the passthru commands above.

Each script creates `workdir`, symlinks the current store-built configuration to
`workdir/config.tf.json`, and invokes the wrapper. The default workdir is the
configuration name, relative to the caller's current directory. Set an explicit
`workdir` when several configurations would otherwise share state.

The development shell captures one generation of store paths. Re-enter it after
changing the Nix configuration; otherwise its scripts keep pointing at the old
JSON. `nix run` evaluates the current flake again and does not have that stale
shell problem.

## Configuration surface

| Option | Purpose |
|---|---|
| `modules` | Terranix/Nix modules evaluated into Terraform JSON |
| `extraArgs` | Extra module arguments, analogous to `specialArgs` |
| `workdir` | Runtime directory for JSON, provider metadata, locks, and state; defaults to the configuration name |
| `terraformWrapper.package` | `pkgs.terraform` by default; use `pkgs.opentofu` or a `withPlugins` package |
| `terraformWrapper.extraRuntimeInputs` | Programs added to the wrapper's `PATH` |
| `terraformWrapper.prefixText` | Shell run before every runtime invocation |
| `terraformWrapper.suffixText` | Shell run after every runtime invocation |
| `terranix.exportDevShells` | Set false to construct devShells manually from `result.devShell` |

Read-only `result` attributes expose `terraformConfiguration`,
`terraformWrapper`, `scripts`, `app`, and `devShell` for custom wiring and
debugging. Prefer these over duplicating the upstream shell scripts.

## Secrets and wrapper commands

Export credentials in `prefixText` from the host's secret provisioning layer:

```nix
{
  terranix.terranixConfigurations.infra = {
    terraformWrapper = {
      package = pkgs.opentofu;
      extraRuntimeInputs = [pkgs.jq pkgs.awscli2];
      prefixText = ''
        export TF_VAR_hcloud_token="$(< /run/secrets/hcloud-token)"
      '';
    };
    modules = [./config.nix];
  };
}
```

`extraRuntimeInputs` is for programs called by prefix/suffix text; the example
`$(< file)` uses Bash itself and needs no `cat` package. Do not place a literal
secret in Nix: the secret and every generated file containing it become
world-readable Nix store entries. State remains sensitive even when the JSON
contains only variable references.

`suffixText` runs after the runtime command and is useful for ordinary cleanup,
not for hiding a failed plan or apply. Preserve the runtime's exit status and
avoid cleanup that would destroy evidence needed to debug a failure.

## Multiple environments

```nix
{
  terranix.terranixConfigurations = {
    staging.modules = [./staging.nix];
    production = {
      modules = [./production.nix];
      terraformWrapper.package = pkgs.opentofu;
    };
  };
}
```

Shared Nix modules can define common options while each environment supplies
its own values, workdir, backend key, and credentials. Separate state is what
limits blast radius; merely importing two modules into one configuration does
not.

For production, use the wrapper to save and review a plan artifact rather than
running the apply app directly. See
[state-and-operations.md](state-and-operations.md).

Sources: [terranix flake module](https://github.com/terranix/terranix/blob/b6c05a45b2435cb3471d6f135ddb0b3c2934cc45/flake-module.nix),
[flake-parts guide](https://terranix.org/docs/getting-started/flake-modules/),
[runtime customization](https://terranix.org/docs/getting-started/terraform-wrapper/).
