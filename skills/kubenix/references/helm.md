# Helm charts in kubenix

Kubenix inflates helm charts **at build time**: `helm template` runs inside a
derivation, and the rendered objects are imported into the same typed
`kubernetes.resources` tree as everything else. There is no helm release
state, no Tiller, no `helm list` — after kubenix renders, helm the tool is
out of the picture. This is what makes the output GitOps- and
air-gap-friendly, and it changes the semantics of CRDs and hooks (below).

## Minimal release

```nix
{ kubenix, ... }: {
  imports = [ kubenix.modules.k8s kubenix.modules.helm ];

  kubernetes.helm.releases.nginx = {
    chart = kubenix.lib.helm.fetch {
      repo    = "https://charts.bitnami.com/bitnami";
      chart   = "nginx";
      version = "15.0.1";
      sha256  = "sKVqx99O4SNIq5y8Qo/b/2xIqXqSsZJzrgnYYz/0TKg=";
    };
    namespace = "web";
    values.replicaCount = 2;
  };
}
```

`kubenix.lib.helm.fetch` is a **fixed-output derivation**: the network fetch
happens once, is hash-pinned, and is then cached in the store. To bump a
chart: set `sha256 = lib.fakeSha256;`, build, paste the hash from the error
message. Proxy env vars are respected. Alternatives to `repo`:

```nix
chart = kubenix.lib.helm.fetch { chartUrl = "https://…/chart-1.2.3.tgz"; sha256 = …; };
chart = ./charts/mychart;                    # vendored local chart directory
chart = "${pkgs.fetchgit { … }}/istio";      # chart inside a fetched repo
```

### Charts as flake inputs

Yes — `chart` is just `types.package` passed to `helm template`, so any store
path works, and flake.lock then does the version pinning instead of a
hand-managed `sha256`:

```nix
# flake inputs — Nix unpacks tarball inputs, and helm template accepts the
# resulting chart directory directly:
inputs.cilium-chart = {
  url = "https://helm.cilium.io/cilium-1.18.4.tgz";
  flake = false;
};
inputs.istio-charts = { url = "github:istio/istio/1.24.2"; flake = false; };

# in the kubenix module:
kubernetes.helm.releases.cilium.chart = inputs.cilium-chart;
kubernetes.helm.releases.istiod.chart = inputs.istio-charts + "/manifests/charts/istio-control/istio-discovery";
```

Bump with `nix flake update cilium-chart` (or `nix flake lock
--update-input …`). Trade-offs versus `helm.fetch`: inputs are pinned in
flake.lock (visible, updatable with standard tooling, shared across
machines), but every chart input is fetched on every flake evaluation —
keep the count small, and prefer `helm.fetch` for charts you reference from
a single module.

## Release options (`kubernetes.helm.releases.<name>`)

| Option | Default | Notes |
|---|---|---|
| `chart` | — | package/store path; required |
| `namespace` | `null` | `--namespace`; with `overrideNamespace = true` (default) also rewrites every object's `metadata.namespace` |
| `values` | `{}` | nested attrset, serialized to a JSON values file |
| `kubeVersion` | `kubernetes.version` | `--kube-version` |
| `apiVersions` | auto from `kubernetes.customTypes` | `--api-versions` — charts can template against your registered CRDs |
| `includeCRDs` | **`false`** | see below |
| `noHooks` | `false` | hooks are rendered as plain objects and **run immediately on apply** — kubenix bypasses the helm CLI, so nothing sequences them. Set `true` unless you want that. |
| `overrides` | `[]` | list of attrsets merged over every rendered object of this release |

## `includeCRDs` — leave it false unless you mean it

Charts bundle CRDs under `crds/`. Helm itself installs those once and
**never updates them** (HIP-0011). Kubenix's default mirrors the safe part
of that behavior by excluding them. If you set `includeCRDs = true`, the
CRDs become ordinary objects in your manifest and every `apply` rewrites
them — including while CRs of those types exist, which can prune data.
Prefer declaring CRDs explicitly yourself (see
[custom-resources.md](custom-resources.md)) where ordering and updates are
your decision.

## Patching chart output

Rendered objects merge into the resource tree, so re-declaring the same
object patches it via module merging — no kustomize needed:

```nix
# the chart rendered a Deployment named "nginx"; tune it here:
kubernetes.resources.deployments.nginx.spec.template.spec.securityContext.fsGroup = 1000;
```

If the object also needs to exist only conditionally, or you need its
options typed, declare it fully — the merge is deep.

## Evaluation consequences (IFD)

`helm template` runs during evaluation (import-from-derivation). Two
practical effects:

- Evaluating a module with helm releases **builds** the chart render first —
  fine for `nix build`, but it makes `nix flake check` unhappy across
  systems (kubenix's own helm test is disabled in its check suite for this
  reason). Keep helm-heavy packages in `packages`, not `checks`.
- Debugging: the render is two derivations, `<name>.yaml` (helm template
  output) then JSON conversion via `yq` (which also strips nulls). Build
  them individually to inspect a bad render.

The helm binary is `pkgs.kubernetes-helm` from whichever nixpkgs the
evaluation is bound to — via `evalModules.${system}` that's kubenix's pinned
nixpkgs; via the overlay it's yours. Chart behavior can differ across helm
versions, so note which one a working setup used.

**Values are written to the nix store as JSON** — world-readable. Never put
secrets in `values`; use vals references (see
[deploy-and-secrets.md](deploy-and-secrets.md)) or runtime env-based
injection in the chart's own values.
