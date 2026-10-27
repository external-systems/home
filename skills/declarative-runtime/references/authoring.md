# Authoring a pairing

All upstream paths below refer to declarative-runtime commit
`0e727d18c6f69f00f9b2786cb09d39d316413847`. Start with upstream
`CLAUDE.md` §“Provider implementation contract”; it is the normative source.
The reusable implementation is in `modules/lib/`; do not recreate it in each
service directory.

## 1. Establish the target and ownership

Read the base NixOS module and the provider's resource documentation at the
pinned versions. Record:

- the primary systemd unit and the API readiness endpoint;
- the service user/group and persistent state directory;
- provider source/version and whether nixpkgs packages it;
- authentication bootstrap and the least-privilege credential needed;
- which existing tool owns each resource after deployment.

A provider's presence in nixpkgs is packaging evidence, not proof that the
pairing is a good design. Check resource support and read/write behavior.

## 2. Create the expected file layout

```text
services/<svc>/
├── module.nix            # services.<svc>.runtime options + systemd wiring
├── lib.nix               # provider block + schema overlay + executor
├── provider-schema.json  # committed normalized provider schema
├── schema.nix            # fromJSON (readFile ./provider-schema.json)
├── fixtures.nix          # desired state shared by snapshots and VM tests
├── checks.nix            # live-API integration tests
├── README.md             # install, examples, options map, updates, secrets
└── pkg.nix               # only when the provider is absent from nixpkgs
```

Wire the module into `modules/default.nix`, export
`nixosModules.<svc> = withSchemaLib ./services/<svc>/module.nix`, register its
`lib.nix` in `pairingLibs`, and merge `checks.nix` into flake checks.
`withSchemaLib` injects the source-only `nix-tf-schema` input through
`_module.args`; a NixOS module cannot otherwise reach that flake input.

Evidence: upstream `flake.nix`, `modules/default.nix`, and `CLAUDE.md:104-126`.

## 3. Package the provider and vendor its schema

Prefer the provider from `pkgs.terraform-providers` when available. Otherwise
follow `services/forgejo/pkg.nix`:

```nix
pkgs.terraform-providers.mkProvider {
  owner = "example-owner";
  repo = "terraform-provider-example";
  rev = "v1.2.3";
  spdx = "MPL-2.0";
  hash = "…";
  vendorHash = "…";
  homepage = "https://github.com/example-owner/terraform-provider-example";
}
```

Pin `required_providers` to the packaged `provider.version`. Build OpenTofu
with the provider baked in so activation needs no registry access:

```nix
executor = pkgs.opentofu.withPlugins (_: [ provider ]);
```

`provider-schema.json` is a normalized `tofu providers schema -json` dump:
sorted with `jq -S`, data sources and the top-level provider block removed,
and `source`/`version` added. Generate it with
`nix run .#update-provider-schemas`, then commit it. Never derive it through
IFD: evaluation must not execute a provider binary, including for a foreign
architecture.

Evidence: `CLAUDE.md:128-154,309-313,368-379`; `services/forgejo/pkg.nix`.

## 4. Describe only what the schema cannot express

`lib.nix` imports the shared helpers and calls `tfSchema.mkResourceTypes`.
Here is the real minimal shape, adapted from Forgejo organizations:

```nix
{ pkgs, nix-tf-schema }:
let
  genlib = import ../../modules/lib { inherit pkgs; };
  tfSchema = import ../../modules/lib/tf-schema.nix {
    inherit pkgs nix-tf-schema;
  };
  provider = pkgs.terraform-providers.example_example;
  providerSource = "example/example";
  providerVersion = provider.version;
  runtimePrefix = "services.example.runtime";
  tokenVar = "example_api_token";
  executor = pkgs.opentofu.withPlugins (_: [ provider ]);

  generated = tfSchema.mkResourceTypes {
    schema = import ./schema.nix;
    inherit provider runtimePrefix;
    source = providerSource;
    resources = {
      things = {
        type = "example_thing";
        prefix = "thing";
        nameAttr = "name";
        scope = null; # or the provider token scope(s)
        refs = { };
        description = "Example things, keyed by name.";
      };
    };
    # Every unmodelled provider resource needs a non-empty reason:
    unsupported.example_legacy = "Provider cannot update this resource safely.";
  };
  inherit (generated) resourceTypes;
in
{
  inherit provider providerSource resourceTypes;
  inherit (generated) checks coverage;
  resourceOptions = genlib.resourceOptions resourceTypes;
  mkReconcileService = args:
    genlib.mkReconcileService (args // { inherit executor tokenVar; });
}
```

The schema supplies settable attributes, Nix types, required/optional status,
nested blocks, sensitive flags, and descriptions. Collections are
`attrsOf (submodule …)` with no freeform escape: misspelled attributes and
wrong types fail evaluation.

The six required collection fields are `type`, `prefix`, `nameAttr`, `scope`,
`refs`, and `description`. Corrections are validated against real schema paths:

- `omit` / provider-wide `omitEverywhere` — drop unsupported or synthetic
  attributes;
- `extraSecrets` / `notSecrets` — correct inaccurate sensitive flags;
- `forceOptional` — deliberate escape when a newly required upstream attribute
  should not break existing configurations;
- `requiredAttrs` — restore non-empty requirements after key/default handling;
- `oneOfRefs` — encode exactly-one constraints absent from the schema;
- `extraAttrs` — last-resort typed overrides, not a freeform resource API.

Do not hand-maintain a parallel list of provider attributes. Provider drift is
meant to fail evaluation with a useful diff.

Evidence: `modules/lib/tf-schema.nix:75-185`; `services/forgejo/lib.nix`.

## 5. Model managed references

A reference input names another managed collection entry. The renderer removes
the input from the resource body and emits the real Terraform attribute as an
interpolation:

```nix
repoRef = {
  attr = "repository_id";
  targets = [
    {
      collection = "repositories";
      field = "id";
    }
  ];
  managedOnly = true;
  required = true;
  description = "Key of the managed repository that owns this resource.";
};
```

- `managedOnly = true` requires a managed sibling; use it for computed numeric
  IDs that have no meaningful literal form.
- `managedOnly = false` accepts either a managed key or a literal name. This
  supports built-ins and externally managed objects.
- Multiple `targets` provide a priority-ordered multi-type reference.
- The resulting `${type.label.field}` reference also gives OpenTofu its apply
  order.

The attrset key defaults `nameAttr`; users should not repeat a resource name
unless overriding it. Computed/output-only provider attributes are not exposed
as desired-state options.

Evidence: `services/forgejo/lib.nix:26-66`; `modules/lib/default.nix` renderer.

## 6. Let the shared renderer handle JSON and dialects

Specialize `genlib.mkTfConfig` with the provider block and call it from
`module.nix`:

```nix
exampleTfConfig = genlib.mkTfConfig {
  inherit resourceTypes providerVersion providerSource runtimePrefix tokenVar;
  providerName = "example";
  providerBlock = cfg: {
    host = cfg.baseUrl;
    api_token = "\${var.${tokenVar}}";
  };
};
```

The result is `{ config; credentials; }`. `config` contains provider/resource
JSON and sensitive variable declarations; `credentials` maps variable IDs to
host paths. It does not contain the credential values.

Two provider schema dialects matter for nested objects:

- **sdk/v2** (Keycloak): nested blocks are under `block.block_types`; a
  singleton list/set block must render as a one-element list.
- **plugin-framework** (Forgejo): nested attributes use `nested_type`; a
  `single` nested object renders as a plain JSON object.

The schema walker derives `blockAttrs`, and the renderer wraps blocks through
nested attrsets and list elements. Do not hand-code one provider's nesting
shape into another pairing.

Evidence: `modules/lib/default.nix:180-450`; `CLAUDE.md:199-212`.

## 7. Wire the NixOS module and reconciler

The pairing adds options under `services.<svc>.runtime` and asserts that the
base service is enabled. Its core wiring follows this Forgejo-derived shape:

```nix
let
  cfg = config.services.example.runtime;
  example = config.services.example;
  tflib = import ./lib.nix { inherit pkgs nix-tf-schema; };
  tf = tflib.exampleTfConfig cfg;
in
{
  options.services.example.runtime = {
    enable = lib.mkEnableOption "declarative Example runtime configuration";
    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8080";
    };
    tokenFile = lib.mkOption {
      type = lib.types.str;
      example = "/run/secrets/example-api-token";
      description = "Target-host credential path, not a Nix store path.";
    };
  } // tflib.resourceOptions;

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = example.enable;
        message = "services.example.runtime requires services.example.enable.";
      }
    ];

    systemd.services.declarative-example = tflib.mkReconcileService {
      name = "declarative-example";
      tfConfig = tf.config;
      inherit (tf) credentials;
      afterUnits = [ "example.service" ];
      healthUrl = "${cfg.baseUrl}/healthz";
      inherit (cfg) tokenFile;
      inherit (example) user group stateDir;
    };
  };
}
```

`mkReconcileService` supplies `after` **and** `requires`, `oneshot` +
`RemainAfterExit`, `restartTriggers = [ confFile ]`, offline `tofu init`, and
`tofu apply -auto-approve -input=false`. It runs as the service user/group and
stores state in `${stateDir}/declarative-terraform`.

For a `DynamicUser` service, pass `dynamicUser = true` and keep `stateDir`
under `/var/lib`; systemd then gives both units the same hashed UID and creates
persistent state through `StateDirectory=`.

### Readiness needs a real completion check

The shared helper polls `healthUrl` with anonymous `curl -fsS` up to 60 times
at two-second intervals. At the researched revision, an exhausted loop falls
through to OpenTofu rather than failing with a clear readiness message. For a
new pairing, use a probe that expresses the service's actual readiness and add
a final unconditional probe before apply. Use authenticated probes when the
API requires them; this can mean specializing the unit rather than reusing the
stock `healthUrl` helper unchanged.

Keep bootstrap in a separate oneshot when credentials must be minted. Persist
its output with mode `0600`, make reruns idempotent, order the reconciler after
it, and document rotation/recovery. Accept operator-supplied credential files
when self-bootstrap is inappropriate.

Evidence: `modules/lib/default.nix:477-569`; `services/forgejo/module.nix`;
`services/keycloak/module.nix`.

## 8. Verify statically and at runtime

After a provider or nixpkgs bump:

```sh
nix run .#update-provider-schemas
nix build .#checks.x86_64-linux.<svc>-schema-current
nix build .#checks.x86_64-linux.<svc>-schema-coverage
nix build .#checks.x86_64-linux.<svc>-options-doc
nix build .#<svc>-rendered-fixtures
```

Diff rendered fixtures and options before/after a surface change. A new
provider resource must be modelled or listed in `unsupported` with a reason.

The behavioral gate is a `pkgs.testers.runNixOSTest` integration test:

1. Boot with the base service and runtime pairing enabled; require no manual
   setup.
2. Wait for `declarative-<svc>.service`.
3. Query the **live service API**, not OpenTofu state, for every important
   resource and reference kind.
4. Restart/reapply and require `0 added, 0 changed, 0 destroyed`.
5. Prove a file-backed secret reached the service and its literal is absent
   from generated `.tf.json`.
6. Exercise a generated-config change, authentication recovery, and readiness
   failure where relevant.

Use the host repo's resource policy for heavy VM tests. A successful eval or
unit-file inspection is not evidence that reconciliation works.

Evidence: `CLAUDE.md:291-303,336-366`; both pairings' `checks.nix`.
