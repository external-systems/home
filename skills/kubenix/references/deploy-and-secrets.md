# Building, deploying, secrets, and air-gap

## Build outputs

An evaluation's config yields (all derivations):

- `config.kubernetes.objects` — the flat, ordered, deduped list of rendered
  resource attrsets (the in-Nix form; order from `kubernetes.resourceOrder`).
- `config.kubernetes.generated` — a single k8s `List` object.
- `config.kubernetes.result` — a JSON file containing that List.
- `config.kubernetes.resultYAML` — a multi-document YAML stream (one `---`-
  separated doc per object). **The one to hand to k3s auto-deploy and most
  GitOps tooling.**

```nix
packages.manifests = (kubenix.evalModules.${system} {
  module = import ./cluster;
}).config.kubernetes.resultYAML;
```

`nix build .#manifests` → `./result` is the YAML. `kubernetes.namespace`
sets a default namespace for all resources; `kubernetes.kubeconfig` points
the CLI at a cluster.

## The kubenix CLI

`packages.default` (override it with your module) wraps the render in a
kubectl driver:

```nix
packages.kubenix = inputs.kubenix.packages.${system}.default.override {
  module = import ./cluster;
  specialArgs = { flake = self; };   # anything extra your modules need
};
```

- `nix run .#kubenix` — interactive: `kubectl diff --prune`, prompt, then
  `kubectl apply --prune`.
- `nix run .#kubenix -- render` / `diff` / `apply` — non-interactive
  subcommands.
- Anything else passes through to kubectl: `nix run .#kubenix -- apply -l
  app=web` applies a label-filtered subset (and `render | kubectl delete -l
  … -f -` removes one).
- `nix build .#kubenix` writes `manifests.json` into the result.
- Every kubectl invocation is fed through `vals eval
  -fail-on-missing-key-in-map` first — vals references in the manifest
  resolve at deploy time, never in the store.

## Secrets

The rule, again, because it's the rule that bites: **kubenix output lives in
the world-readable nix store. Plaintext secrets must never be rendered into
it.** The built-in pattern is vals references resolved at apply time:

```nix
kubernetes.resources.secrets.example.stringData = {
  password = "ref+file:///run/secrets/db-password";
  token    = "ref+vault://secret/data/myapp#/token";
};
```

The kubenix CLI resolves these via `vals eval` as it pipes to kubectl.
Compositions that work well:

- **sops / sops-nix**: let sops-nix decrypt to a runtime path on the deploy
  host (`sops.secrets.<name>.path`, e.g. under `/run/secrets/`), and put
  `ref+file://<that path>` in the manifest. The manifest in the store holds
  only the reference.
- **clan vars generators** (this fleet's secret backend): a generator's
  output file has a stable runtime path —
  `config.clan.core.vars.generators.<gen>.files.<file>.path` (under
  `/run/secrets/vars/...`). Wire the two in the same NixOS module: the
  generator produces the secret on the host, the kubenix manifest carries
  only a vals reference to it, and the CLI's `vals eval` resolves it at
  apply time:

  ```nix
  { config, ... }: {
    clan.core.vars.generators.db-password = {
      files.password.secret = true;
      script = "cp $prompts/password $out/password";  # human runs `clan vars generate`
    };

    # in the kubenix module (same evaluation has access to config.clan…):
    # kubernetes.resources.secrets.db.stringData.password =
    #   "ref+file://${config.clan.core.vars.generators.db-password.files.password.path}";
  }
  ```

  Same discipline as sops: the manifest holds the reference, never the
  value. Remember agents must never run `clan vars generate` — generation
  is a human step; the manifest only needs the *path*, which is known at
  eval time.
- **sealed-secrets / external-secrets**: no kubenix integration exists, but
  they're just resources — declare the `SealedSecret` (with the *sealed*,
  already-encrypted payload, which is safe to store) or `ExternalSecret`
  typed via `kubernetes.customTypes`, and let the in-cluster controller
  materialize the real Secret. This keeps plaintext out of both the store
  and git.
- **Helper functions**: `kubenix.lib.k8s.mkSecretOption` and
  `kubenix.lib.k8s.secretToEnv` build `valueFrom.secretKeyRef` env wiring
  for consuming Secrets — referencing, never storing.

## Deploying to k3s / RKE2

k3s auto-deploys every manifest found in
`/var/lib/rancher/k3s/server/manifests`. On a NixOS k3s server:

```nix
{
  environment.etc."kubenix.yaml".source =
    (inputs.kubenix.evalModules.x86_64-linux {
      module = import ./cluster;
    }).config.kubernetes.resultYAML;

  system.activationScripts.kubenix.text = ''
    mkdir -p /var/lib/rancher/k3s/server/manifests
    ln -sf /etc/kubenix.yaml /var/lib/rancher/k3s/server/manifests/kubenix.yaml
  '';
}
```

Two caveats, both real:

- k3s applies added/changed manifests but **does not delete resources when a
  file is removed** — no pruning. For deletion semantics use the CLI
  (`apply --prune`) or a GitOps controller instead of the manifests dir.
- The file is a symlink into the nix store: world-readable, no secrets.

RKE2 has the same auto-deploy mechanism at
`/var/lib/rancher/rke2/server/manifests` — same pattern, same caveats.

k3s/RKE2's bundled helm-controller (`helm.cattle.io` `HelmChart` CRDs) is an
alternative renderer, but mixing it with kubenix's build-time inflation
duplicates the job. If you want typed `HelmChart`/`HelmChartConfig`
resources instead (letting the cluster's controller do the rendering),
register them via `kubernetes.customTypes` — group `helm.cattle.io`, version
`v1`. Prefer one rendering pipeline per cluster.

## GitOps with FluxCD

Kubenix and Flux fit cleanly because kubenix's output is plain static YAML —
Flux needs no helm controller involvement at all. The two patterns that
work:

1. **Rendered-manifest repo** (recommended): kubenix renders `resultYAML` in
   CI (or locally on deploy), the YAML is committed to the cluster repo, and
   a Flux `Kustomization` with `sourceRef` on the repo applies the directory.
   No kustomize needed — a Flux Kustomization applies plain YAML as-is.
   Split into multiple Kustomizations with `dependsOn` for layering:
   CRDs/infrastructure first, apps after (see the CRD lifecycle rules in
   [custom-resources.md](custom-resources.md) — CRDs get their own
   Kustomization, optionally with `spec.crds: CreateReplace`).
2. **OCI artifact**: build the manifest as a Flux `OCIArtifact` source
   (push `resultYAML` with `flux push artifact` in CI) — versioned,
   checksummed, and natural for air-gapped transfer.

Practical notes:

- Flux prunes by default (`prune: true`), which fixes the k3s manifests-dir
  deletion gap.
- Kubenix's `kubenix/hash` label only changes when content changes, so it
  doesn't fight Flux's drift detection. Leave `addHashLabel` on.
- Don't commit vals `ref+…` manifests to a repo Flux applies — Flux doesn't
  resolve vals. Either resolve during the render step in CI (so committed
  YAML is complete — meaning that repo is now secret-bearing, usually wrong)
  or prefer the in-cluster patterns (sealed-secrets / external-secrets)
  for Flux-managed clusters.

## Bootstrap: kubenix for the CNI, Flux for everything after

A working bootstrap split: kubenix renders the bootstrap layer (CNI, Flux
itself, CRDs), Flux takes over continuous reconciliation once it's running.

1. Configure k3s for a BYO CNI: `services.k3s.extraFlags = [
   "--flannel-backend=none" "--disable-network-policy" ]` (add
   `--disable-kube-proxy` if running Cilium with kube-proxy replacement).
2. Inflate the Cilium chart in kubenix (`kubernetes.helm.releases.cilium`,
   chart via flake input or `helm.fetch`, `kubeVersion` matching the
   cluster) and render it together with the Flux install manifests
   (`flux install --export` output, imported via `kubernetes.imports`).
3. Apply that bootstrap manifest once — k3s manifests dir or the kubenix
   CLI — wait for Cilium and Flux to come up.
4. From then on, Flux owns everything, *including Cilium upgrades*: commit
   the Cilium YAML to the Flux repo and **remove it from the k3s manifests
   dir / stop applying it with the CLI**. Two owners of the same objects is
   the failure mode here — k3s's deployer and Flux will both "fix" drift in
   opposite directions. One resource, one owner.

The same pattern works for RKE2 (`--disable rke2-canal` etc.) and for
seed-crds-then-apps layering generally.

## Air-gapped installs

Full recipe in [images.md](images.md#air-gapped-recipe). The short version:
helm charts are fixed-output derivations (fetch once, hash-pinned), images
are dockerTools derivations pushed with skopeo or exported as OCI archives,
`docker.useVals = false` drops the runtime vals dependency, and the manifest
closure transfers with `nix copy`. Evaluation and rendering then need no
network at all.

## Debugging renders

- Eval error against `io.k8s...` options — the generated bindings mirror the
  OpenAPI spec of your `kubernetes.version`; check field names/types against
  that exact k8s version's API docs.
- Inspect intermediate helm output by building the `<name>.yaml` /
  `<name>.json` render derivations directly (see
  [helm.md](helm.md#evaluation-consequences-ifd)).
- `kubernetes.addHashLabel = false` if the `kubenix/hash` label confuses
  label selectors or diffs.
