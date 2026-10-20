# Submodules: reusable, versioned module bundles

Reach for this when a group of resources (an app, a namespace scaffold, a
standard monitoring stack) recurs across clusters or projects. The
`submodule`/`submodules` pair is kubenix's packaging system: a registry of
named, versioned modules with typed arguments, instantiated by name.

It's a separate axis from `kubernetes.customTypes`: customTypes type
*resources*; submodules package *config*.

## Defining a submodule

```nix
# modules/webapp.nix — a reusable bundle
{ kubenix, lib, config, ... }: {
  imports = [ kubenix.modules.submodule kubenix.modules.k8s ];

  submodule = {
    name = "webapp";
    version = "1.2.0";
    exports = {   # what the parent can read back after instantiation
      serviceName = config.submodule.args.name;
    };
  };

  options.submodule.args = {
    name  = lib.mkOption { type = lib.types.str; };
    image = lib.mkOption { type = lib.types.str; };
    port  = lib.mkOption { type = lib.types.int; default = 8080; };
  };

  config.kubernetes.resources = {
    deployments.${config.submodule.args.name}.spec.template.spec.containers.app = {
      image = config.submodule.args.image;
      ports.http.containerPort = config.submodule.args.port;
    };
    services.${config.submodule.args.name} = { … };
  };
}
```

A submodule module must import `kubenix.modules.submodule` and set
`submodule.name`; `version` (default `"1.0.0"`), `tags`, `exports`, and
`passthru` are the remaining registry metadata. Typed `submodule.args` are
the public interface — treat everything else as internal.

## Registering and instantiating

```nix
{ kubenix, ... }: {
  imports = [ kubenix.modules.k8s kubenix.modules.submodules ];

  submodules.imports = [ ./modules/webapp.nix ];

  submodules.instances = {
    frontend = {
      submodule = "webapp";              # or { name = "webapp"; version = "~1\\..*"; }
      args = { name = "frontend"; image = "registry/app:1.4"; };
    };
    admin = {
      submodule = "webapp";
      args = { name = "admin"; image = "registry/app:1.4"; port = 9090; };
    };
  };

  # read back exports:
  # config.submodules.instances.frontend.submodule.exports.serviceName
}
```

- Version matching: `"~regex"` pins instance to a compatible submodule
  version.
- **`submodule.passthru`** lets an instance push config *up* to the parent
  evaluation (e.g. extra `kubernetes.objects` computed from args) — the
  channel for things exports can't express.
- Instances are evaluated as nested kubenix evaluations (`kubenix.evalModules`
  under the hood), so each instance is its own module-system scope.
- Defaults propagation: `_m.features` / `_m.propagate` (from the `base`
  module) pass defaults between parent and child evals — this is how a
  parent-wide `kubernetes.namespace` can flow into instances.
- Every object an instance emits gets labeled `kubenix/module-instance`,
  `kubenix/module-name`, `kubenix/module-version` automatically — which
  makes `nix run .#kubenix -- apply -l kubenix/module-instance=frontend`
  work out of the box.

## When to reach for it

- Same bundle in several clusters/flakes → submodule, versioned.
- One-off resources in one cluster → plain `kubernetes.resources`.
- Bundle needs to emit differently-shaped config per consumer → typed
  `submodule.args` plus `passthru`.
