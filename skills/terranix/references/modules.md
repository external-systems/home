# Modules, references, and lifecycle blocks

## Choose the module system deliberately

Terranix modules and Terraform modules solve different problems:

- A **terranix module** is NixOS-style Nix. Use it for typed options,
  conditional configuration, functions, and reuse across flakes.
- A **Terraform module** is an external HCL/JSON child module called through a
  `module` block. Use it to consume an existing registry, Git, or local module.

Importing a Nix file into `terranixConfigurations.<name>.modules` does not call
a Terraform module, and setting `module.<name>.source` does not import Nix.

## Author terranix modules

```nix
{config, lib, ...}: let
  cfg = config.example.web;
in {
  options.example.web = {
    enable = lib.mkEnableOption "the example web bucket";
    name = lib.mkOption {
      type = lib.types.str;
      description = "Globally unique bucket name.";
    };
  };

  config = lib.mkIf cfg.enable {
    resource.aws_s3_bucket.web.bucket = cfg.name;
    output.web_bucket_name.value = lib.tf.ref "aws_s3_bucket.web.bucket";
  };
}
```

A module can contain `imports`, `options`, and `config`. Compose reusable
options under a namespace owned by the module. Values such as `resource`,
`data`, `provider`, `variable`, `output`, `module`, and `terraform` are freeform
Terraform JSON-shaped options; provider arguments retain their provider schema
names.

Definitions merge recursively across Nix modules. Attrsets merge, lists
concatenate, and incompatible definitions at one path produce a module type
error. `null` values are removed by default. Empty top-level `resource`, `data`,
and `ephemeral` types are omitted, while an empty nested block such as
`features = {};` remains significant. Only Terraform's supported top-level
blocks reach the JSON; custom option values must be mapped into one of them.

On current main, use the built-in `assertions` and `warnings` options to report
configuration problems together. This self-contained example gives the option
a default so evaluation reaches the assertion:

```nix
{config, lib, ...}: {
  options.example.web.name = lib.mkOption {
    type = lib.types.str;
    default = "example";
  };

  assertions = [{
    assertion = config.example.web.name != "";
    message = "example.web.name must not be empty";
  }];
  warnings = ["example.web is an example interface"];
}
```

These built-ins are post-2.9.0 main features at the researched revision. For
2.9.0, `lib.mkAssert condition "message" {...}` guards a value or config block.
Do not redefine top-level `assertions` or `warnings` options on current main.

## Distinguish Nix values from runtime references

Nix and Terraform both use `${...}`. Escape Terraform expressions so Nix leaves
them for plan/apply:

| Desired result | Terranix expression |
|---|---|
| Reference in a double-quoted string | `"\${aws_instance.web.id}"` |
| Escape inside a Nix `'' ... ''` string | `''${aws_instance.web.id}` |
| Reference through a helper | `lib.tf.ref "aws_instance.web.id"` |
| Resource attribute through the module system | `config.resource.aws_instance.web "id"` |
| Read the literal Nix `image` value now | `config.resource.aws_instance.web.image` |

`lib.tfRef` is a compatibility alias for `lib.tf.ref`. Prefer `lib.tf.ref` in
new modules. `config.resource.<type>.<name> "attr"` has existed since terranix
2.7.0 and produces a runtime reference; reading `.attr` directly instead reads
the Nix value during JSON generation. Named `config.variable.<name>` and
`config.module.<name> "output"` references are main-only after 2.9.0, so use
`lib.tf.ref` for released-version compatibility.

For non-secret files and templates:

```nix
{lib, ...}: {
  resource.hcloud_ssh_key.example.public_key =
    lib.tf.ref (lib.tf.file ./id_ed25519.pub);

  resource.local_file.rendered.content = lib.tf.ref (lib.tf.template {
    text = "address=\${address}\n";
    variables.address = "192.0.2.10";
  });
}
```

`tf.file` emits a Terraform `file(...)` call and `tf.template` emits
`templatefile(...)`; `tf.ref` wraps either call as a complete string value.
Paths are copied into the Nix store, so use them only for public or non-secret
material.

## Consume external Terraform modules

Registry example:

```nix
{lib, ...}: {
  module.network = {
    source = "terraform-aws-modules/vpc/aws";
    version = "~> 6.0";
    cidr = "10.0.0.0/16";
    azs = ["eu-central-1a" "eu-central-1b"];
    private_subnets = ["10.0.1.0/24" "10.0.2.0/24"];
    public_subnets = ["10.0.101.0/24" "10.0.102.0/24"];
  };

  output.vpc_id.value = lib.tf.ref "module.network.vpc_id";
}
```

`source` accepts the normal registry, Git, HTTP, S3, and local module source
forms. Other attributes are child-module input variables or module
meta-arguments. Match the child module's documented variable names and types;
terranix does not generate those inputs from Nix options. Registry modules need
a `version` constraint. Review a module's own required providers and runtime
floor before adopting it.

Relative sources resolve from the runtime **workdir**, not from the Nix file
that declared them. For example, with `workdir = "terraform/prod"`,
`source = "../modules/network"` resolves to `terraform/modules/network`. Keep
local HCL modules at that resolved path, or use a pinned registry/Git source.
The generated `config.tf.json` being a store symlink does not change this
working-directory rule.

## Share terranix modules through flakes

The upstream publishing convention is:

```nix
{
  outputs = {self, ...}: {
    terranixModules.network = ./modules/network.nix;
    terranixModule.imports = [self.terranixModules.network];
  };
}
```

Consumers add `inputs.network.terranixModule` or selected
`terranixModules.<name>` values to their terranix `modules` list. Use
`terranix.lib.terranixOptions` to generate `options.json` for module
documentation.

## State lifecycle blocks

Terranix serializes these blocks but does not enforce the runtime version.
Set `terraform.required_version` and check both runtime and provider floors.

| Block | Purpose | Terraform | OpenTofu |
|---|---|---|---|
| `moved` | Rename or relocate an address without recreate | 1.1+ | 1.6+ |
| `import` | Adopt an existing object | 1.5+ | 1.6+ |
| `removed` | Remove an address from state, optionally without destroying | 1.7+ | 1.7+ |
| `ephemeral` | Use ephemeral resources/values | 1.10+ | 1.11+ |

Addresses in `moved`, `import`, and `removed` blocks are literal addresses, not
interpolation expressions:

```nix
{
  terraform.required_version = ">= 1.7";

  moved = [{
    from = "aws_instance.old";
    to = "aws_instance.web";
  }];

  import = [{
    to = "aws_s3_bucket.existing";
    id = "my-existing-bucket";
  }];

  removed = [{
    from = "aws_instance.retired";
    lifecycle.destroy = false;
  }];
}
```

Plan every lifecycle change and inspect the resulting state/action diff. A
`removed` block with `destroy = false` intentionally abandons ownership while
leaving the object alive. An import is complete only when the configuration
matches the imported object and the plan is clean. Write-only arguments require
Terraform or OpenTofu 1.11+ and provider support; do not infer them from the
presence of `ephemeral` blocks alone.

## Inspect and evaluate without applying

`terranix.lib.evalTerranixConfiguration` returns
`{config, assertions, warnings, _meta;}` without writing a store derivation:

```nix
let
  result = terranix.lib.evalTerranixConfiguration {
    system = "x86_64-linux";
    modules = [./config.nix];
  };
in result.config
```

Use it in `nix repl` to inspect the attrset. `terranixConfiguration` returns the
JSON derivation with the same fields as passthru attributes. The deprecated
`terranixConfigurationAst`, `buildTerranix`, and `buildOptions` functions warn
and are scheduled for removal in 3.0.0; use `evalTerranixConfiguration`,
`.config`, and `terranixOptions` instead.

Sources: [core evaluation](https://github.com/terranix/terranix/blob/b6c05a45b2435cb3471d6f135ddb0b3c2934cc45/core/default.nix),
[Terraform-shaped options](https://github.com/terranix/terranix/blob/b6c05a45b2435cb3471d6f135ddb0b3c2934cc45/core/terraform-options.nix),
[reference helpers](https://github.com/terranix/terranix/blob/b6c05a45b2435cb3471d6f135ddb0b3c2934cc45/core/helpers.nix),
[flake library](https://github.com/terranix/terranix/blob/b6c05a45b2435cb3471d6f135ddb0b3c2934cc45/flake/lib.nix),
[Terraform module sources](https://developer.hashicorp.com/terraform/language/modules/sources),
[terranix module guide](https://terranix.org/docs/getting-started/modules/).
