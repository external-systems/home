# Observability, Extensibility & Troubleshooting — Envoy Gateway v1.9.2

All extension CRDs are `apiVersion: gateway.envoyproxy.io/v1alpha1`.
Note: v1.9.2 has no FAQ page; `troubleshooting/` contains only
`admin-console.md`, `configuration.md`, `envoy-proxy-admin-interface.md`
(a `faq.md` appears post-1.9 on main).

## 1. Data-plane telemetry on the EnvoyProxy CRD

EnvoyProxy attached via `GatewayClass.spec.parametersRef` or
`Gateway.spec.infrastructure.parametersRef`.

### Access logs — `spec.telemetry.accessLog`

- `disable: true` turns logging off.
- `settings[]` entries: `format` (`type: Text` + `text:` template, or
  default JSON), `sinks[]`, `matches[]` (CEL expressions), and `type`
  (`Route` | `Listener`).
- Sink types: `OpenTelemetry` (`openTelemetry.host`, `port: 4317`),
  `ALS` (gRPC Access Log Service: `als.backendRefs[]` + `als.type:
  HTTP`), and File (default file log goes to `/dev/stdout`).
- **Default JSON format** keys: `start_time, method,
  x-envoy-origin-path, protocol, response_code, response_flags,
  response_code_details, connection_termination_details,
  upstream_transport_failure_reason, bytes_received, bytes_sent,
  duration, x-envoy-upstream-service-time, x-forwarded-for, user-agent,
  x-request-id, :authority, upstream_host, upstream_cluster,
  upstream_local_address, downstream_local_address,
  downstream_remote_address, requested_server_name, route_name`.
- Once any custom `settings` entry exists, the default file access log
  is removed — re-enable per component with an empty entry (`- type:
  Route`).
- Gateway-API metadata operators in formats:
  `%METADATA(ROUTE:envoy-gateway:resources)%`.

### Metrics — `spec.telemetry.metrics`

- Prometheus enabled by default: Envoy admin `/stats/prometheus` on pod
  port **19001** (container port name `metrics`). Pod labels:
  `gateway.envoyproxy.io/owning-gateway-namespace`,
  `gateway.envoyproxy.io/owning-gateway-name`; also
  `app.kubernetes.io/name=envoy`, `app.kubernetes.io/component=proxy`.
- `telemetry.metrics.prometheus.disable: true`; OTel sink:
  `telemetry.metrics.sinks: [{type: OpenTelemetry, openTelemetry: {host,
  port: 4317}}]`.

### Tracing — `spec.telemetry.tracing`

- Providers: `OpenTelemetry` (port 4317), `Zipkin` (port 9411),
  `Datadog` (port 8126). Off by default.
- `samplingRate` (percent) and `samplingFraction: {numerator,
  denominator}` for sub-1%.
- OTel-only sampler: `provider.openTelemetry.sampler.type` ∈ `AlwaysOn |
  AlwaysOff | TraceIdRatio | ParentBased*` — when set, the sampler is
  the sole decision maker.
- v1.9.0 breaking change: tracing client sampling default 100% → **0%**
  (opt in via `clientSamplingFraction`).

### Health check logs — `spec.telemetry.healthCheckLog`

- JSON events via Envoy `event_logger`. Empty `{}` → `/dev/stdout`.
- `matches` values: `Failure`, `FailureSeriesStart`, `Success`,
  `HealthyTransition`. Omitted = log every probe.
- Scope: **xRoute-backed clusters only**. Technical backends (ext-auth,
  ext-proc, JWKS, OIDC token) use
  `backendSettings.healthCheck.active.healthCheckLog` on the owning
  policy.
- Override: `BackendTrafficPolicy.spec.healthCheck.active.healthCheckLog`
  takes precedence over EnvoyProxy-level for that cluster.

## 2. Control-plane & Gateway API observability

### Control-plane metrics (EnvoyGateway config)

- Prometheus on by default; port-forward control-plane pod
  (`control-plane=envoy-gateway`) 19001 → `GET /metrics`.
- Exported metric families:
  - Watching: `watchable_depth`, `watchable_subscribe_duration_seconds`,
    `watchable_subscribe_total`, `watchable_panics_recovered_total` —
    label `runner` ∈ `gateway-api | infrastructure | xds-server |
    xds-translator | global-ratelimit`.
  - Status Updater: `status_update_total`,
    `status_update_duration_seconds` (label `kind`).
  - xDS Server: `xds_snapshot_create_total`,
    `xds_snapshot_update_total`, `xds_stream_duration_seconds`,
    `xds_nack_total` (labels `nodeID`, `streamID`, `isDeltaStream`).
  - Infra Manager: `resource_apply_total`,
    `resource_apply_duration_seconds`, `resource_delete_total` (labels
    `kind`, `name`, `namespace`).
  - Wasm cache: `wasm_cache_entries`, `wasm_cache_lookup_total`,
    `wasm_remote_fetch_total`.
  - Topology injector webhook: `topology_injector_webhook_events_total`.

### Gateway API state metrics

- Enable: `--set prometheus.kube-state-metrics.enabled=true` on
  `gateway-addons-helm` (Kuadrant gateway-api-state-metrics). Metrics
  like `gatewayapi_gateway_status{type="Accepted"}`,
  `gatewayapi_gateway_listener_info{protocol="HTTP"}`. Grafana
  dashboards: grafana.com IDs 19432, 19433, 19434, 19570.

### Gateway API → XDS metadata

- Stored under `metadata.filter_metadata.envoy-gateway.resources` on
  XDS resources. Contents: Kind, Namespace, Name, Annotations (only
  keys with `gateway.envoyproxy.io/` prefix), SectionName.
- Mapping: VirtualHost←`Gateway` (sectionName=listener name);
  Route←`HTTPRoute`/`GRPCRoute` (rule name); Cluster←xRoute (or
  owning policy for non-xRoute backendRefs); LBEndpoints←`Service`/
  `ServiceImport`/`Backend`.

### Rate-limit observability

- RateLimit service Prometheus on port **19001**. Metrics:
  `ratelimit_service_rate_limit_{total_hits, over_limit, near_limit,
  within_limit, shadow_mode}` — labels `domain`, `key1`, `key2` only by
  default (**high-cardinality warning** on descriptor keys like client
  IPs). Emits **histogram families**; use `..._count` with `rate()`.
- Tracing off by default; configure in **EnvoyGateway** config:
  `rateLimit.telemetry.tracing` — default sampling 100% (perf risk).

## 3. Extensibility

### EnvoyPatchPolicy — unstable, disabled by default

- Kind `EnvoyPatchPolicy`, `spec.targetRef` → Gateway (or GatewayClass
  when `mergeGateways` enabled). `type: JSONPatch`, `jsonPatches[]`:
  `type` (xDS proto URL e.g.
  `type.googleapis.com/envoy.config.listener.v3.Listener`), `name` (xDS
  resource name), `operation`: `op` + either `path` (JSON pointer) or
  `jsonPath` (regex-filtered selector) + `value`. `priority: 0` default.
- Enable: EnvoyGateway config `extensionApis.enableEnvoyPatchPolicy:
  true`, then restart envoy-gateway.
- **xDS Name Scheme V2**: gated by runtime flag `XDSNameSchemeV2`;
  disabled by default in v1.9, **enabled by default in v1.10** — migrate
  patch policies. Old names: `<GatewayNamespace>/<GatewayName>/<ListenerName>`;
  V2: listeners `tcp-80`, RouteConfig/HCM `http-<Port>`/`https-<Port>`.
- **Security warning**: arbitrary config/code injection, SSRF,
  credential access (CVE-2026-22771 / GHSA-xrwg-mqj6-6m22). Mitigate
  with RBAC, disabling unneeded envoy extensions via cmdline,
  NetworkPolicies, admission control, audit logging. Always unstable:
  xDS API fields deprecate, EG translation/naming changes.
- Debug: status conditions `Accepted=True`, `Programmed=True`; offline
  validation via `egctl x translate`.

### Extension Server

- gRPC server EG calls **before** sending xDS to Envoy. Hooks (enable
  in `extensionManager.hooks.xdsTranslator.post[]`): `Route`, `Cluster`
  (custom backends only), `VirtualHost`, `HTTPListener`, `Translation`.
  Execution order: Route→Cluster→VirtualHost→HTTPListener→Translation.
- Policy CRDs registered via `extensionManager.policyResources[]`.
  Attach via `targetRef(s)` (+`sectionName`) — same-namespace only — or
  `targetSelectors` (cross-namespace allowed but requires a
  `ReferenceGrant` in the target's namespace).
- Gateway-targeted and route-targeted policies are **not merged** —
  conflict resolution is the extension server's job.
- Multiple servers: `extensionManagers[]` (plural) with unique `name`;
  sequential chaining. Same CVE-2026-22771 security warning applies.
- Post-1.9: `service.timeout` bounds hook calls — without it an
  unreachable server blocks xDS translation and `failOpen` never fires.

### Wasm — via EnvoyExtensionPolicy `spec.wasm[]`

- Fields: `name`, `rootID`, `code`: `type: HTTP` (`http.url`,
  `http.sha256`) or `type: Image` (`image.url`, OCI). Runtime fixed to
  **v8**.
- Image build: single-layer image required — Dockerfile `FROM scratch`
  + exactly one `COPY plugin.wasm ./`.
- v1.9.1: OCI Wasm pulls require HTTPS (no implicit HTTP fallback).

### Lua — disabled by default

- Enable: `extensionApis.enableLua: true`.
  `EnvoyExtensionPolicy.spec.lua[]`: `type: Inline` (`inline:` script)
  or `type: ValueRef` (ConfigMap key `lua`).
- v1.9.0: Lua source moved from per-route `LuaPerRoute` to
  listener-level filters (filter names changed).
- v1.9.2 breaking: scripts using `getfenv`/`setfenv`/`newproxy`/`module`
  fail `Strict` Lua validation (default); set
  `EnvoyProxy.spec.lua.validationType: InsecureSyntax|Disabled` to
  bypass.
- Warning: no strong sandboxing; recommend RBAC + admission control.

### Dynamic Modules

- Load `.so` into Envoy: `EnvoyProxy.spec.dynamicModules[]`: `name`,
  `source: {type: Local, local: {path}}`, `doNotClose`, `loadGlobally`.
  Deliver the `.so` via image volume (K8s **1.35+** only), custom image,
  or initContainer+shared volume.
- Configure filter: `EnvoyExtensionPolicy.spec.dynamicModule[]`:
  `name`, `filterName`, `config`.

### External Processing

- `EnvoyExtensionPolicy.spec.extProc[]`: `backendRefs` (gRPC service),
  `processingMode`: default sends nothing; `request: {}` = request
  headers; `response: {body: Streamed}` = response headers + streamed
  body. `messageTimeout` default 200ms, `failOpen` default false,
  `statusOnError` default 500. TLS via `BackendTLSPolicy`.

### OPA sidecar over UDS

- Requires `extensionApis.enableBackend: true` (Backend CRD for UDS
  endpoints). `Backend` with `spec.endpoints: [{unix: {path:
  /shared/opa/opa.sock}}]`.
- `EnvoyProxy.spec.filterOrder`: `- {name:
  envoy.filters.http.ext_authz, after: envoy.filters.http.jwt_authn}`
  so OPA sees JWT-derived headers.
- Sidecar injected via `envoyDeployment.patch` (StrategicMerge): shared
  `emptyDir` socket volume, `runAsUser: 65532` (match Envoy container
  UID).

### Remote Infrastructure Provider

- EnvoyGateway config: `provider.type: Custom`,
  `custom.resource.type: Kubernetes`, `custom.infrastructure.type:
  Remote`, `remote.service`.
- Security: provider receives full infra IR for every Gateway — run as
  sidecar/private channel, least privilege.

## 4. Troubleshooting toolkit

### egctl

- `egctl config envoy-proxy <type>` — live xDS dump from all proxies.
  `egctl config envoy-gateway all|gateway -n envoy-gateway-system` —
  control-plane in-memory resources via the EG admin config-dump
  endpoint.
- `egctl x status <type>` (experimental): types `xRoute|HTTPRoute|
  GRPCRoute|TLSRoute|TCPRoute|UDPRoute`, `xPolicy|BackendTLSPolicy|
  BackendTrafficPolicy|ClientTrafficPolicy|EnvoyPatchPolicy|
  SecurityPolicy`, `all|GatewayClass|Gateway`. Flags: `--quiet`,
  `--verbose`, `-A/--all-namespaces`, `-n`.
- `egctl x dashboard envoy-proxy -n envoy-gateway-system <pod>` →
  Envoy admin UI at `http://localhost:19000`. `egctl x dashboard eg` →
  EG admin console.
- `egctl x translate --from gateway-api --to gateway-api|ir|xds -f -` —
  offline translation/validation. `-t route|cluster|listener|...`
  filters output; `--add-missing-resources` synthesizes dummy resources
  and emits a starter `EnvoyProxy` with default bootstrap (admin
  127.0.0.1:19000, xds_cluster → `envoy-gateway:18000` w/ SDS certs
  under `/sds/`, DELTA_GRPC). Known trap: TLS-listener Gateway +
  HTTPRoute yields an **empty** RoutesConfigDump.

### Admin interfaces

- **Envoy proxy admin**: listens on localhost:19000 in the proxy pod
  (container also serves `/stats/prometheus` on 19001). Port-forward:
  ```sh
  kubectl port-forward deploy/$(kubectl get deploy -n envoy-gateway-system \
    --selector=gateway.envoyproxy.io/owning-gateway-namespace=<ns>,gateway.envoyproxy.io/owning-gateway-name=<gw> \
    -o jsonpath='{.items[0].metadata.name}') -n envoy-gateway-system 19000:19000
  ```
  then `/config_dump`, etc.
- **Envoy Gateway admin console**: auto-enabled on localhost:19000 of
  the control-plane pod. `kubectl port-forward -n envoy-gateway-system
  deployment/envoy-gateway 19000:19000` or `egctl x dashboard eg`.
  Features: dashboard (auto-refresh 30s), server info, config dump,
  stats at `/api/metrics`, pprof when enabled. Config via EnvoyGateway
  `spec.admin.address.{host,port}` and `spec.admin.enablePprof`
  (enable only for debugging — sensitive).

### Configuration troubleshooting workflow

1. Check `status` on every resource — e.g. HTTPRoute `Accepted: True`
   but `ResolvedRefs: False / BackendNotFound` ("Service
   default/backend-does-not-exist not found").
2. `egctl x status all -A` for a fleet-wide condition view;
   kube-state-metrics for scale.
3. Traffic symptom: rejected config → route gets `direct_response` →
   client sees **HTTP 500**; access log shows `"response_code": 500,
   "response_code_details": "direct_response"`.
4. Proxy pod log selector: `kubectl logs -n envoy-gateway-system -l
   gateway.envoyproxy.io/owning-gateway-namespace=<ns>,gateway.envoyproxy.io/owning-gateway-name=<gw>
   -c envoy`.

### Flags on maturity

- Experimental: all `egctl x ...` subcommands; `EnvoyPatchPolicy`
  explicitly "always unstable"; Extension Server + Remote Infra
  Provider carry full-compromise security warnings; Lua off by default
  (weak isolation); dynamic-module image volumes need K8s 1.35+;
  extension-server policy targeting TCPRoute/UDPRoute/TLSRoute not
  supported; Gateway-API metadata currently holds only the primary
  origin resource.
