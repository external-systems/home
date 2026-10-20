---
name: kubenix
description: "Kubenix (github.com/hall/kubenix): render Kubernetes manifests with the Nix module system — declaring typed resources (kubernetes.resources), inflating Helm charts at build time (kubernetes.helm.releases + kubenix.lib.helm.fetch), wiring Nix-built dockerTools OCI images into manifests and pushing them with skopeo, typed Custom Resources via kubernetes.customTypes, building YAML/JSON manifests, deploying to k3s/RKE2, air-gapped/offline installs, and composing secrets (vals refs, sops, sealed-secrets). Load whenever the user mentions kubenix, wants k8s manifests from Nix instead of YAML/helm template by hand, or asks how to ship Nix-built images or helm charts to a cluster — including airgapped k3s/RKE2."
---

# kubenix

Kubenix renders Kubernetes manifests through the NixOS module system: you
declare typed resources in Nix, kubenix evaluates them against bindings
generated from the Kubernetes OpenAPI spec, and emits a manifest you feed to
`kubectl apply`, k3s auto-deploy, or a GitOps tool. Repo:
[hall/kubenix](https://github.com/hall/kubenix), docs:
[kubenix.org](https://kubenix.org/).

**Project status:** pre-1.0 and explicitly unstable ("expect breaking
changes"). Latest tag is 0.3.0; `main` carries unreleased pre-0.4.0 breaking
changes (CHANGELOG `[Unreleased]` — registry option restructure, deferredModule
customTypes, copyScript binary rename). There is no 0.4.0 branch or tag — pin
a kubenix rev in the flake and read the CHANGELOG when bumping. Generated
bindings exist for k8s **1.19–1.36**; `kubernetes.version` selects them
(default: latest).

## The one rule: the nix store is world-readable

Everything kubenix renders lands in `/nix/store`, readable by every user on
the machine. **Secrets never go inline** — not in `values`, not in
`stringData`. Put `ref+...` [vals](https://github.com/variantdev/vals)
references in the manifest and resolve them at apply time; the kubenix CLI
already pipes every render through `vals eval` for exactly this reason. See
[references/deploy-and-secrets.md](references/deploy-and-secrets.md).

## Mental model

One evaluation in, one manifest out:

```nix
# flake.nix (consumer)
inputs.kubenix.url = "github:hall/kubenix";

# perSystem packages:
packages.manifests = (inputs.kubenix.evalModules.${system} {
  module = { kubenix, ... }: {
    imports = [ kubenix.modules.k8s ];
    kubernetes.version = "1.32";
    kubernetes.resources.nginx = {
      spec.containers.nginx.image = "nginx:1.27";
      spec.containers.nginx.ports.http.containerPort = 80;
    };
  };
}).config.kubernetes.resultYAML;  # multi-doc YAML; .result is a JSON List
```

`nix build .#manifests` leaves the rendered YAML at `./result`. Everything
— helm output, CRs, plain resources — converges into the same typed resource
tree before rendering, so the same patching, defaults, and ordering rules
apply to all of it.

Evaluation entry points:

- `kubenix.evalModules.${system} { module = …; }` — binds kubenix's pinned
  nixpkgs.
- `kubenix.overlays.default` — gives `pkgs.kubenix.evalModules` bound to
  *your* nixpkgs (preferred when your images/packages must share one pkgs).
- Non-flake: `import <kubenix>` (flake-compat) or
  `import kubenix/lib/eval-modules.nix { inherit pkgs; }`.
- **No flake-parts module is exported** — kubenix uses flake-parts
  internally only. In a flake-parts consumer, wire it yourself in
  `perSystem.packages` via the overlay or `evalModules.${system}`.

Inside a module you always get these arguments: `kubenix` (with `.modules`,
`.lib` = `{k8s, docker, helm}`, `.evalModules` for nested evals), `pkgs`,
`lib` (extended with `importYAML`, `toYAML`, `toMultiDocumentYaml`,
`toBase64`).

## Declaring resources

Two addressing styles, same tree:

```nix
# latest-version alias (generated camelCase plural):
kubernetes.resources.deployments.nginx.spec.replicas = 2;
# full GVK path (needed for older versions and CRs):
kubernetes.resources."apps"."v1".Deployment.nginx.spec.replicas = 2;
```

Conventions that differ from raw YAML — internalize these, they are where
most kubenix mistakes happen:

- **Lists with a merge key become attrsets.** `containers`, `env`, `ports`,
  `volumeMounts`, `volumes`… are attrsets keyed by `name`, coerced back to
  ordered lists at render. You write `spec.containers.nginx.image`, never a
  list. Merging and overriding come from the module system for free.
- `apiVersion`, `kind`, and `metadata.name` default from where you hang the
  resource — `kubernetes.resources.pods.nginx = { };` is a valid Pod.
- `null` values and attrs starting with `_` are stripped at render
  (exception: `_` survives in ConfigMap `data`/`binaryData`). Use `mkIf` and
  `mkDefault` exactly as in NixOS modules.
- Every object gets a `kubenix/hash` label (`kubernetes.addHashLabel =
  false` to disable); `kubernetes.enableHashedNames = true` gives immutable
  hashed ConfigMap/Secret names.
- `kubernetes.api.defaults` sets defaults for every matching resource (list
  of `{resource, default}` — `default` may itself be a module, so
  conditional defaults work). `kubernetes.resourceOrder` (default CRDs then
  Namespaces first) controls the emitted object order.

## Where each topic lives

Load the reference for the branch you're on:

- **Helm charts** — inflating charts at build time, fetching/version-pinning
  them (including charts as flake inputs), patching rendered output,
  `includeCRDs`/`noHooks` semantics:
  [references/helm.md](references/helm.md)
- **Nix-built OCI images** — dockerTools images into manifests, registries,
  the skopeo push script, why flake inputs are the wrong shape for images:
  [references/images.md](references/images.md)
- **CRDs & typed Custom Resources** — `kubernetes.customTypes`,
  multi-version kinds, importing CRD YAML:
  [references/custom-resources.md](references/custom-resources.md)
- **Building & deploying manifests, secrets, air-gap, k3s/RKE2, GitOps** —
  `result`/`resultYAML`, the kubenix CLI, vals/sops/clan-vars/sealed-secrets,
  offline recipes, k3s manifests-dir, FluxCD handoff and CNI bootstrap:
  [references/deploy-and-secrets.md](references/deploy-and-secrets.md)
- **Reusable module bundles** — the submodule/submodules registry for
  packaging groups of resources with typed args:
  [references/submodules.md](references/submodules.md)

## Fast diagnostics

- Type error naming `io.k8s...` options: you hit the generated bindings —
  check the field name/type against the matching k8s API docs for your
  `kubernetes.version`; kubenix types mirror the OpenAPI spec exactly.
- Helm release changes not appearing: helm renders via
  import-from-derivation — the chart render must *build* during evaluation,
  so helm modules can't be evaluated in pure `nix flake check` across
  systems. Build locally per-system instead.
- A field silently missing from output: it was `null` or `_`-prefixed, or
  you set it at a level the schema doesn't define (kubenix would normally
  type-error — silent drops mean you escaped the typed tree, e.g. via
  freeform CRs).
