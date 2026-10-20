# CRDs and typed Custom Resources

Kubenix types built-in resources from generated OpenAPI bindings.
`kubernetes.customTypes` extends the same typing to your own kinds: you
register group/version/kind plus a Nix module describing the schema, and
instances of that kind get the full module-system treatment (type errors at
eval, defaults, merging).

Two different jobs are easy to confuse:

1. **Installing the CRD into the cluster** — a CRD manifest like any other
   resource.
2. **Typing custom resources in Nix** — `kubernetes.customTypes`, which is
   purely eval-time schema. Registering a type does not emit a CRD manifest;
   declaring a CRD manifest does not type its CRs. You usually do both.

## Typing custom resources

```nix
{ kubenix, lib, ... }: {
  imports = [ kubenix.modules.k8s ];

  kubernetes.customTypes = [{
    group    = "stable.example.com";
    version  = "v1";
    kind     = "CronTab";
    attrName = "cronTabs";       # alias under kubernetes.resources
    module = {                   # a NixOS-style module defining the SPEC
      options.cronSpec = lib.mkOption { type = lib.types.str; };
      options.image    = lib.mkOption { type = lib.types.str; };
      options.replicas = lib.mkOption { type = lib.types.int; default = 1; };
    };
  }];

  kubernetes.resources.cronTabs.my-cron = {
    spec.cronSpec = "* * * * */5";
    spec.image = "my-cron-image";
  };
}
```

Details that matter:

- The default `module` type is `freeformType = attrs` — omit `module` and
  instances are untyped attrsets. Add a module when you want eval-time
  checking; it's worth it for anything you'll touch repeatedly.
- **`kubernetes.customTypesModuleDefinesCRDSpec`** (default `true`): your
  module defines only `spec`, and kubenix wraps it with
  `apiVersion`/`kind`/`metadata` (metadata typed as real `ObjectMeta`).
  Set it `false` to define the whole resource yourself (`spec`, `status`,
  …) — the escape hatch for operators with nonstandard shapes.
- `metadata.name` defaults to the attribute key, as with built-in kinds.

## Addressing and multiple versions

Each customType creates a canonical option at
`kubernetes.resources."<group>"."<version>".<Kind>`. Additionally, the
**latest** version of each `attrName` gets the shortcut
`kubernetes.resources.<attrName>` (versions are compared with
`compareVersions`).

```nix
kubernetes.customTypes = [
  { group = "g.io"; version = "v1"; kind = "Widget"; attrName = "widgets"; … }
  { group = "g.io"; version = "v2"; kind = "Widget"; attrName = "widgets"; … }
];

kubernetes.resources.widgets.w = { … };                        # v2 (latest)
kubernetes.resources."g.io"."v1".Widget.w-old = { … };         # explicit v1
```

## Installing the CRD manifest itself

Two ways:

```nix
# (a) typed, via the generated apiextensions bindings:
kubernetes.resources.customResourceDefinitions."crontabs.stable.example.com" = {
  spec.group = "stable.example.com";
  spec.names = { kind = "CronTab"; plural = "crontabs"; };
  spec.scope = "Namespaced";
  spec.v1 = { /* schema … */ };
};

# (b) import existing YAML (also the way to adopt any third-party manifest):
kubernetes.imports = [ ./crds/crontab.yaml ];
```

`kubernetes.imports` parses YAML (IFD via `yq`) and routes each document
into the resource tree, so imported objects are patchable like everything
else.

Ordering: `kubernetes.resourceOrder` defaults to putting
`CustomResourceDefinition` first (then `Namespace`), so CRDs land before
their CRs in the emitted list.

## Interplay with helm

Registered `customTypes` are automatically passed to `helm template` as
`--api-versions`, so charts that conditionally render CR support (e.g.
`{{- if .Capabilities.APIVersions.Has }}`) see them. See
[helm.md](helm.md) — and remember `includeCRDs` stays false by default, so
the CRD itself is still your explicit resource.
