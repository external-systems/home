# Install & Operations — Envoy Gateway v1.9.2

Verified from tag `v1.9.2`. Docs root: `site/content/en/latest/` in the
envoyproxy/gateway repo.

## Shipped versions (verified from source)

- **Envoy proxy (data plane)**: `docker.io/envoyproxy/envoy:distroless-v1.39.1`
  default in `api/v1alpha1/shared_types.go` (`DefaultEnvoyProxyImage`);
  v1.9.2 release notes instruct `distroless-v1.39.3`.
- **Gateway API (sig-network)**: `sigs.k8s.io/gateway-api v1.6.1` (go.mod);
  bundled CRDs carry annotation
  `gateway.networking.k8s.io/bundle-version: v1.6.1`. Default channel shipped
  by the chart is **experimental** (includes alpha kinds `TCPRoute`,
  `BackendTLSPolicy`).
- **Ratelimit sidecar image**: `docker.io/envoyproxy/ratelimit:0482748e`
  (helm default).
- Kubernetes v1.33–v1.36 supported.

## Install methods

### Helm (recommended) — `install/install-helm.md`

Chart: `oci://docker.io/envoyproxy/gateway-helm`.

```shell
helm install eg oci://docker.io/envoyproxy/gateway-helm --version <helm-version> -n envoy-gateway-system --create-namespace
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
kubectl apply -f https://github.com/envoyproxy/gateway/releases/download/<version>/quickstart.yaml -n default
```

- Default install applies BOTH Gateway API CRDs (experimental channel) and
  Envoy Gateway CRDs. If a provider manages Gateway API CRDs, verify
  compatibility via CRD annotations, then install only EG CRDs and use
  `--set crds.enabled=false`.
- Privileged listener ports (<1024) are mapped internally to unprivileged
  ports — no extra privileges needed.
- Check provider-installed Gateway API CRDs:

```shell
kubectl get crd gateways.gateway.networking.k8s.io -o go-template='version={{ index .metadata.annotations "gateway.networking.k8s.io/bundle-version" }} channel={{ index .metadata.annotations "gateway.networking.k8s.io/channel" }}{{ "\n" }}'
```

- Common `--set` keys: `config.envoyGateway.extensionApis.enableBackend=true`
  (Backend API off by default), `deployment.replicas=2`,
  `kubernetesClusterDomain=<domain>`.

### YAML — `install/install-yaml.md`

```shell
kubectl apply --server-side -f https://github.com/envoyproxy/gateway/releases/download/<version>/install.yaml
```

`install.yaml` includes Gateway API + EG CRDs. Do NOT use when a provider
manages Gateway API CRDs. Less configurable than Helm.

### Argo CD — `install/install-argocd.md`

`Application` (`argoproj.io/v1alpha1`) with `source.chart: gateway-helm`,
`repoURL: docker.io/envoyproxy`, `targetRevision: <version>`,
`destination.namespace: envoy-gateway-system`, syncOptions
`CreateNamespace=true`, `ServerSideApply=true` (SSA required to dodge the
262,144-byte annotation limit). Values via `source.helm.valuesObject`; skip
CRDs with `source.helm.skipCrds: true`.

### Flux — `install/install-flux.md`

`OCIRepository` (`source.toolkit.fluxcd.io/v1`)
`url: oci://docker.io/envoyproxy/gateway-helm` with
`layerSelector.mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip`,
`operation: copy`, `ref.tag: <version>`; `HelmRelease`
(`helm.toolkit.fluxcd.io/v2`) `releaseName: eg`, `chartRef` → OCIRepository,
`upgrade.strategy.name: RetryOnFailure`. Skip CRDs: `spec.install.crds: Skip`
(and `spec.upgrade.crds: Skip`). Values via `spec.values`.

### egctl — `install/install-egctl.md`

Binaries from GitHub releases; script:
`curl -fsSL https://gateway.envoyproxy.io/get-egctl.sh | VERSION=<v> bash`;
or `brew install egctl`.

## CRDs-only chart — `install/gateway-crds-helm-api.md`

Chart `oci://docker.io/envoyproxy/gateway-crds-helm`. All values:

| key | default |
|---|---|
| `crds.gatewayAPI.enabled` | `false` |
| `crds.gatewayAPI.channel` | `"experimental"` (alt: `standard`) |
| `crds.envoyGateway.enabled` | `false` |

Install via template+apply (Helm limitation with large CRDs in
`templates/`, helm/helm#12277):

```shell
helm template eg oci://docker.io/envoyproxy/gateway-crds-helm --version <v> \
  --set crds.gatewayAPI.enabled=true --set crds.gatewayAPI.channel=standard \
  --set crds.envoyGateway.enabled=true | kubectl apply --server-side -f -
```

Then main chart with `--set crds.enabled=false`. Note: Gateway API
"safe upgrade" ValidatingAdmissionPolicy+binding are rendered by the main
chart on install by default (disable when externally managed).

## gateway-helm values structure — `install/gateway-helm-api.md`

Key paths (defaults):

- `crds.enabled: true` — installs EG CRDs, Gateway API CRDs, safe-upgrade
  policy resources.
- `config.envoyGateway` — EnvoyGateway config object: defaults
  `gateway.controllerName: gateway.envoyproxy.io/gatewayclass-controller`,
  `logging.level.default: info`, `provider.type: Kubernetes`,
  `extensionApis: {}`.
- `deployment.replicas: 1`; `deployment.ports`: grpc 18000, ratelimit 18001,
  wasm 18002, metrics 19001; probes on `:8081` (`/healthz`, `/readyz`,
  startup failureThreshold 30); resources requests `100m/256Mi`, limits
  memory `1024Mi`; securityContext runAs 65532 non-root,
  readOnlyRootFilesystem, drop ALL caps;
  `deployment.envoyGateway.wasmCacheVolume` (default emptyDir at
  `/var/lib/eg/wasm`, PVC-able).
- `certgen` — job (ttlSecondsAfterFinished 30) generates control-plane
  certs; does not overwrite pre-existing custom Secrets; **do not disable**
  (breaks OIDC/OAuth2).
- `global.imageRegistry`, `global.imagePullSecrets`;
  `global.images.{envoyGateway,envoyProxy,ratelimit}.{image,pullPolicy,pullSecrets}`
  — `envoyProxy.image` rewrites the generated EnvoyProxy config data-plane
  image only.
- `hpa.{enabled:false,minReplicas:1,maxReplicas:1,metrics,behavior}`
  (controller HPA).
- `kubernetesClusterDomain: cluster.local`; `namespaceOverride: ""`;
  `createNamespace: false`; `service.type: ClusterIP`;
  `service.trafficDistribution`; `podDisruptionBudget.minAvailable: 0`;
  `topologyInjector.enabled: true`; `commonLabels: {}`.

## gateway-addons chart — `install/gateway-addons-helm-api.md`

Observability stack: fluent-bit 0.56.0 (`enabled: true`), grafana 10.5.15
(`enabled: true`, admin/admin, anonymous Admin, LoadBalancer svc), loki
7.3.0 (`enabled: true`, SingleBinary), tempo 1.3.1, prometheus 29.10.1
(`enabled: true`, kube-state-metrics CustomResourceStateMetrics for
Gateway/GatewayClass/HTTPRoute/GRPCRoute/TCPRoute/TLSRoute), alloy 1.11.1
(`enabled: false`), opentelemetry-collector 0.169.0 (`enabled: false`,
receivers otlp/envoyals:9000/datadog:8126/jaeger/zipkin, exporters
otlp→tempo, otlphttp→loki, prometheus :19001).

## Upgrade procedure

Helm does not update CRDs in `/crds`. Order: **CRDs first, then Envoy
Gateway** (else new CRD versions not found → reconcile failures).

```shell
helm template eg-crds oci://docker.io/envoyproxy/gateway-crds-helm --version <v> \
  --set crds.gatewayAPI.enabled=true --set crds.envoyGateway.enabled=true \
  | kubectl apply --force-conflicts --server-side -f -
helm upgrade eg oci://docker.io/envoyproxy/gateway-helm --version <v> -n envoy-gateway-system
```

⚠ **v1.9 upgrade caveat**: EG reconciles `TCPRoute`/`UDPRoute` via
`gateway.networking.k8s.io/v1` (promoted in Gateway API v1.6). Gateway API
CRDs must be at v1.6 before upgrading EG, or TCP/UDP routes are silently
skipped. Standard channel: `v1alpha2` no longer served — migrate manifests
to `v1` first or traffic drops. Experimental channel: both served. Storage
version moved `v1alpha2`→`v1`; migrate etcd storage:

```shell
kubectl get tcproutes.gateway.networking.k8s.io -A -o json | kubectl replace -f -
kubectl get udproutes.gateway.networking.k8s.io -A -o json | kubectl replace -f -
```

## Certificates — `install/custom-cert.md` + helm-api certgen

- Default: chart's certgen job generates control-plane TLS before EG
  starts. Secret names are FIXED: `envoy-gateway` (controller), `envoy`
  (data plane), `envoy-rate-limit`, all in `envoy-gateway-system`. Chart
  consumes pre-created Secrets; certgen leaves existing Secrets untouched
  (keep it enabled).
- cert-manager flow: selfsigned Issuer → CA Certificate `envoy-gateway-ca`
  → CA Issuer `eg-issuer` → three `Certificate`s. Controller cert dnsNames:
  `envoy-gateway`, `.envoy-gateway-system`, `.svc`, `.svc.cluster.local`;
  proxy/ratelimit certs use `commonName: "*"`, dnsName
  `*.envoy-gateway-system`. Usages: digital signature, data encipherment,
  key encipherment, content commitment. Only helm override needed:
  `kubernetesClusterDomain` aligned with cert DNS names.
- Rotation: with cert-manager, rotation is automatic (renewal updates the
  fixed Secrets); with certgen, certs are generated once at install — no
  documented in-place rotation procedure beyond rerunning install/upgrade
  flows.

## Deployment modes — `tasks/operations/deployment-mode.md`

- **One GatewayClass per controller** (simplest); **multiple GatewayClasses
  per controller** supported (issue #1231); **separate controllers per
  namespace** for multi-tenancy (unique `gateway.controllerName` + watch
  restriction).
- **Merged gateways**: `spec.mergeGateways: true` on the EnvoyProxy
  attached to GatewayClass → all Gateway listeners under one GatewayClass
  share ONE envoy fleet + single IP. Constraint: (port, protocol, hostname)
  tuple unique across listeners. Docs recommend **ListenerSet** instead for
  new deployments (Gateway API-native, removes the 64-listener limit).
  `mergeGateways` is incompatible with Gateway-attached EnvoyProxy and with
  Gateway Namespace Mode.
- Default watch model: controller watches ALL namespaces, creates
  data-plane resources in controller namespace. Restrict via
  `EnvoyGateway.provider.kubernetes.watch.namespaces` or
  `.namespaceSelector` (watch `type: Namespaces|NamespaceSelector`);
  controller namespace always included.
- Multi-tenancy helm pattern:

```shell
helm install --set config.envoyGateway.gateway.controllerName=gateway.envoyproxy.io/marketing-gatewayclass-controller \
  --set config.envoyGateway.provider.kubernetes.watch.type=Namespaces \
  --set config.envoyGateway.provider.kubernetes.watch.namespaces={marketing} \
  eg-marketing oci://docker.io/envoyproxy/gateway-helm --version <v> -n marketing --create-namespace
```

- Managed data-plane resources labeled:
  `gateway.envoyproxy.io/owning-gateway-namespace`,
  `gateway.envoyproxy.io/owning-gateway-name`,
  `gateway.envoyproxy.io/owning-gatewayclass` (merged mode).

## Gateway Namespace Mode — `tasks/operations/gateway-namespace-mode.md`

Enable: `config.envoyGateway.provider.kubernetes.deploy.type:
GatewayNamespace`. Data plane (Deployment/Service/ServiceAccount) created
in each Gateway's namespace. Added via issue #2629.

- Security model changes from mTLS to **server-side TLS + projected
  service-account JWT** (TokenReview): proxy pods authenticate via
  short-lived audience-specific JWT; only CA cert mounted in gateway
  namespaces.
- ⚠ **Not supported** with Merged Gateways.
- RBAC: helm auto-creates ClusterRole/Binding
  `gateway-helm-cluster-infra-manager` (serviceaccounts/services/configmaps,
  deployments/daemonsets, HPAs/PDBs: create/get/delete/deletecollection/patch;
  tokenreviews: create). With explicit `watch.namespaces` →
  namespace-scoped Roles; with `watch.namespaceSelector` → ClusterRole.

## Standalone mode — `tasks/operations/standalone-deployment-mode.md`

⚠ **Experimental — DO NOT use in production.** Only file provider + host
infra provider combos.

- `envoy-gateway certgen --local [--config-home <dir>]` (default
  `~/.config/envoy-gateway/certs/`).
- `envoy-gateway server --config-path standalone.yaml` with `EnvoyGateway`
  (`gateway.envoyproxy.io/v1alpha1`) config: `provider.type: Custom`,
  `custom.resource.type: File` (`file.paths: [...]`),
  `custom.infrastructure.type: Host` (XDG dirs: configHome
  `~/.config/envoy-gateway`, dataHome `~/.local/share/envoy-gateway`,
  stateHome `~/.local/state/envoy-gateway`, runtimeDir
  `/tmp/envoy-gateway-${UID}`). Requires `extensionApis.enableBackend:
  true` (Backend API represents local endpoints). Any file change under
  watched paths triggers update.

## EnvoyProxy CRD data-plane customization — `tasks/operations/customize-envoyproxy.md`

Kind `EnvoyProxy`, `apiVersion: gateway.envoyproxy.io/v1alpha1`. Attach via
`Gateway.spec.infrastructure.parametersRef` (group `gateway.envoyproxy.io`,
kind `EnvoyProxy`) or `GatewayClass.spec.parametersRef` (with namespace).
Create EnvoyProxy BEFORE referencing it (avoids temporary disruption).
`mergeGateways: true` not allowed on Gateway-attached EnvoyProxy.

Spec fields:

- `spec.provider.type: Kubernetes`, `spec.provider.kubernetes`:
  - `envoyDeployment.replicas` (omitted from generated Deployment when HPA
    active; leave unset when using external autoscalers/KEDA)
  - `envoyDeployment.container.{image,resources,env,volumeMounts}`
    (default env: `ENVOY_POD_NAMESPACE`, `ENVOY_POD_NAME`)
  - `envoyDeployment.pod.{annotations,volumes,priorityClassName}`
  - `envoyDeployment.patch.{type: StrategicMerge, value: <partial
    Deployment>}` — patches containers `envoy` and `shutdown-manager`
  - `envoyService.{annotations,patch}` (patch type `StrategicMerge`)
  - `envoyHpa.{minReplicas,maxReplicas,metrics}` — requires
    metrics-server; when set, `envoyDeployment.replicas` is ignored (use
    `minReplicas` as floor)
  - `envoyDaemonSet` — DaemonSet-based data plane (disabled by default)
- `spec.bootstrap.type`: `Replace` (full bootstrap string in `value`),
  `Merge` (strategic merge into default), `JSONPatch` (`jsonPatches` RFC
  6902). Get default bootstrap via `egctl x translate`; errors surface in
  GatewayClass status.
- `spec.extraArgs`: extra envoy CLI flags.
- `spec.filterOrder`: list of `{name, before|after}` entries reordering
  the default HTTP filter chain.
- `spec.ipFamily`: `IPv4 | IPv6 | DualStack` (backend IP selection follows
  the backendRef Service spec).
- `spec.mergeGateways: true` (see deployment modes).

## Graceful shutdown — `tasks/operations/graceful-shutdown.md`

Shutdown-manager sidecar in every envoy pod. Sequence: SIGTERM → listener
drain (`/drain_listeners?graceful&skip_exit`) → `/healthcheck/fail`
(readiness fails) → poll `server.total_connections` → exit at zero conns
or drain timeout.

EnvoyProxy `spec.shutdown` (defaults):

- `drainTimeout: 60s` — max drain time
- `minDrainDuration: 10s` — min wait before exit allowed
- `healthCheckFailureDelay: 0s` — delay before failing health checks; does
  NOT extend drain

Known bug: hostNetwork + PreStop hook (kubernetes/kubernetes#134285).

## egctl operations — `tasks/operations/egctl.md`

All subcommands beyond `config` are `egctl x ...` (**experimental**):

- `egctl config envoy-proxy <route|...>` — live xDS config dump from
  proxies; `egctl config envoy-gateway <all|gateway|...> -n
  envoy-gateway-system` — EG in-memory resources via admin config-dump.
- `egctl x status <gatewayclass|gateway|httproute|grpcroute|tlsroute|tcproute|udproute|xroute|backendtlspolicy|backendtrafficpolicy|clienttrafficpolicy|envoypatchpolicy|securitypolicy|xpolicy|all>`
  flags: `--quiet` (latest condition only), `--verbose`
  (message/generation/timestamps), `-A/--all-namespaces`, `-n`.
- `egctl x dashboard envoy-proxy -n <ns> <pod>` — opens Envoy admin on
  localhost:19000.
- `egctl x install` — installs workload + CRDs; flags `--skip-crds`,
  `--only-crds`, `--name`, `--namespace` (multi-tenant; use `--skip-crds`
  if CRDs exist).
- `egctl x uninstall` — workload only; `--with-crds` also removes CRDs.
- `egctl x translate --from gateway-api --to <gateway-api|ir|xds> [-t
  route|...] [-f -|--add-missing-resources]` — offline translation incl.
  default bootstrap generation for bootstrap customization.

## Air-gap — `tasks/operations/airgap-deployment.md`

- Control plane: `deployment.envoyGateway.image.{repository,tag}` or
  `global.imageRegistry` (highest precedence, also covers ratelimit);
  `global.images.ratelimit.image`; pull secrets via
  `global.imagePullSecrets` or per-image
  `global.images.<name>.pullSecrets`.
- Data plane: MUST attach an EnvoyProxy with
  `envoyDeployment.container.image` pointing at the internal registry
  (otherwise envoy image pulls implicitly from Docker Hub).
- Default data-plane Service type is `LoadBalancer` — adjust
  type/annotations per environment via `envoyService`.

## Ports reference

Envoy Gateway: xDS proxy server 18000 (not configurable), xDS ratelimit
18001, admin 19000 (127.0.0.1, configurable), metrics 19001, health 8081.
Envoy proxy pods: admin 19000, stats 19001, shutdown-manager 19002,
readiness 19003.

## Flags & caveats summary

- **Experimental**: standalone mode ("do not use in production"); all
  `egctl x *` subcommands; Gateway API experimental channel (default)
  includes alpha TCPRoute/BackendTLSPolicy.
- **Not supported**: Gateway Namespace Mode + mergeGateways;
  mergeGateways on Gateway-level (infrastructure.parametersRef) EnvoyProxy.
- **Deprecated direction**: docs steer new deployments from
  `mergeGateways` to ListenerSet.
- Backend API (`extensionApis.enableBackend`) off by default — required
  for standalone and Backend backendRefs.
