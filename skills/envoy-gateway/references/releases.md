# Releases, Compatibility & Upgrade Notes — Envoy Gateway

Sources: `gateway.envoyproxy.io/news/releases/notes/v1.9.{0,1,2}`,
support policy `news/releases/`, compatibility matrix
`news/releases/matrix/`, main-branch docs diffed against v1.9.2.

## Support policy & cadence

- Semver v2. Minor releases quarterly, aligned to Envoy Proxy's
  schedule.
- Each minor release branch is **supported for 6 months** from release
  date (no LTS).
- **1.9.x**: released 2026-08-14, **EOL 2027-02-14**. 1.8.x EOL
  2026-11-14. 1.10.x expected 2026-10-29.

## Compatibility matrix (v1.9)

| Component | v1.9 | v1.8 (prev) |
|---|---|---|
| Envoy Proxy | **distroless-v1.39.x** (v1.9.2 instructs v1.39.3) | distroless-v1.38.x |
| Gateway API (sig-network) | **v1.6.1** | v1.5.1 |
| Kubernetes | v1.33–v1.36 | v1.32–v1.35 |

- EG ships/tests against exactly one Envoy minor version; other Envoy
  versions are untested.
- Gateway API CRDs come from the **experimental channel** by default
  (alpha resources TCPRoute, BackendTLSPolicy). Helm value
  `crds.gatewayAPI.channel=standard|experimental`.

## v1.9.0 (2026-08-14) — breaking changes

- **Gateway API v1.6 CRD upgrade is mandatory**: TCPRoute/UDPRoute
  reconciled via `gateway.networking.k8s.io/v1`; **silently skipped**
  if v1.6 CRDs absent. `sessionPersistence.idleTimeout` removed
  upstream — manifests must drop it.
- `ClientTrafficPolicy.spec.clientIPDetection` requires exactly one of
  `xForwardedFor` | `customHeader` | `directSourceIP` (CEL; empty `{}`
  rejected).
- Gateway API safe-upgrades `ValidatingAdmissionPolicy` moved from CRD
  bundle into gateway-helm chart templates; two upgrade cases require
  Helm ownership annotations or
  `crds.gatewayAPI.safeUpgradePolicy.enabled=false`.
- SDS reference secret `url` must include `unix://` scheme.
- **Lua EnvoyExtensionPolicies disabled by default**: new
  `extensionApis.enableLua`; `disableLua` deprecated.
- JWT provider/requirement xDS names now content-derived/stable —
  EnvoyPatchPolicy/extension-server refs to old route-derived names
  must update.
- DNS clusters now use `envoy.extensions.clusters.dns.v3.DnsCluster`
  extension.
- `EndpointSliceIndex` runtime flag **on by default** (higher
  controller memory).
- All-`System` CA resources now share one SDS secret
  `system_ca_certificates`; opt-out via `PerResourceSystemCASecret`.
- Tracing client sampling default 100% → **0%** (opt in via
  `clientSamplingFraction`).
- `mergeType` admission validation stricter: only xRoute targets.
- `SecurityPolicy.spec.apiKeyAuth.extractFrom` stricter: ≥1 entry,
  exactly one of headers/params/cookies per entry.
- Lua source moved from per-route `LuaPerRoute` to listener-level
  filters (filter names changed).

## v1.9.0 — new features (selected)

- `SecurityPolicy.spec.csrf` — Origin validation for mutating requests.
- CEL expressions + path matching in SecurityPolicy authorization
  rules; `spec.oidc.forwardIDToken`; JWT `failOpen`.
- `ClientTrafficPolicy`: `directSourceIP`,
  `headers.host.stripTrailingHostDot`,
  `tls.clientValidation.allowExpiredCertificate`, new client timeouts
  (`ConnectionInspectionTimeout`/`RequestHeadersReceivedTimeout`/
  `TLSHandshakeTimeout`).
- **ListenerSet as targetRef kind** in ClientTrafficPolicy,
  SecurityPolicy, BackendTrafficPolicy, EnvoyExtensionPolicy
  (experimental).
- `EnvoyProxy.spec.mergeBackends` — cluster dedup across routes;
  experimental, off by default.
- `BackendTrafficPolicy`: `healthCheck.http.requestBody`,
  `rateLimit.global[].limit.fromMetadata`, ORCA out-of-band
  (`backendUtilization.outOfBand`), `responseOverride.match.responseHeaders`,
  rate limit unit `Week`.
- `Backend.spec.tls.autoSNIFromEndpointHostname`; `DynamicResolver`
  Backend referenced by TLSRoute; `rateLimit.backend.redis.urlRef`.
- SDS certificate refs (`gateway.envoyproxy.io/sds` Secret type; gated
  by `enableSDSSecretRef`).
- `xdsServer.maxReceiveMessageSize`; xDS gRPC default receive limit
  4MiB → **32MiB**.
- New metric `xdsNACKTotal`.

## v1.9.1 (2026-08-28) — critical upgrade notes

- **Reverts the 0s SDS/RDS initial-fetch timeout from v1.9.0** (back
  to Envoy default 15s). **v1.9.0→v1.9.1 in-place upgrade breaks TLS
  on running proxies** (envoyproxy/envoy#47309): ~15s after new
  controller pushes config, TLS listeners go active without certs, pods
  stay Ready. Mitigations: v1.8.x users skip 1.9.0 and go straight to
  1.9.1; v1.9.0 users set EnvoyProxy
  `envoyDeployment.strategy`/`envoyDaemonSet.strategy` to `{type:
  RollingUpdate, rollingUpdate: {maxSurge: 100%, maxUnavailable: 0}}`.
  Detect bad pods: `envoy_sds_init_fetch_timeout > 0`; failing TLS:
  `increase(envoy_listener_server_ssl_socket_factory_downstream_context_secrets_not_ready[5m]) > 0`.
- **HTTP no longer allowed as OIDC issuer URL scheme**; OCI Wasm pulls
  require HTTPS.
- Security: OIDC session cookies switch AES-256-CBC → **AES-256-GCM**
  (CVE-2026-47775 padding oracle); existing sessions invalidated.
- Global rate-limit cluster now built from in-cluster
  `envoy-ratelimit` Service/EndpointSlices via **EDS** (fallback
  STRICT_DNS).

## v1.9.2 (2026-09-28)

- Envoy Proxy → **v1.39.3**; upgrade paths: Helm `--set
  global.images.envoyProxy.image=docker.io/envoyproxy/envoy:distroless-v1.39.3`,
  `envoy-gateway-config` ConfigMap, or per-`EnvoyProxy` resource.
- **Breaking**: Lua scripts using `getfenv`/`setfenv`/`newproxy`/
  `module` now fail `Strict` Lua validation (default); set
  `EnvoyProxy.spec.lua.validationType: InsecureSyntax|Disabled`.
- Security: new **`EnvoyProxyPatch` runtime flag** (enabled by default
  = legacy behavior; multi-tenant clusters should add it to
  `runtimeFlags.disabled` — EnvoyProxy `patch` fields can leverage the
  controller's privileged SA).
- Fixes: duplicate filter-chain matcher; merged-Gateway HTTPS/TLS same
  port+hostname; local rate-limit Distinct selectors cache raised
  20 → **10,000** per-value buckets; CA bundle dedup per gateway.

## Post-1.9 (main branch, targets 1.10 — flag as newer than v1.9.2)

- **`ClusterSettings` renamed `BackendSettings`**;
  `BackendTrafficPolicy.spec.backendSettings` gains **`http3:
  {mode: Auto|Always}`** — backend (upstream) HTTP/3 over QUIC, TLS
  required.
- **`requestBuffer.mode: BufferAndLimit|LimitOnly`** — LimitOnly raises
  the buffer cap without full buffering (streaming/upgrade-safe).
- **`ClientTrafficPolicy.spec.maxRequestHeaderLimit`** (default 60Ki;
  → Envoy `max_request_headers_kb`; 431 response).
- **OIDC `cookieNames`** to pin Envoy's `<Purpose>-<suffix>` cookie
  names.
- **CORS `allowOriginRegexes`** (RE2).
- **Registered Wasm modules**: `EnvoyProxy.spec.wasmModules[]`;
  EnvoyExtensionPolicy `wasm[].name` may omit `code`.
- **Extension server call timeout** `service.timeout`.
- **`debounce{after: 100ms, max: 10s}`** in EnvoyGateway config.
- JWT claim-to-header: `claimPath` (string array) alternative to
  `claim`.
- BackendTrafficPolicy `mergeType` also allowed when targeting backends
  (Service/ServiceImport/Backend).
- New `troubleshooting/faq.md`; `gatewayapi-support.md` moved
  `tasks/traffic/` → `concepts/`.
- `XDSNameSchemeV2` runtime flag becomes **default-on in v1.10** —
  migrate EnvoyPatchPolicies to new xDS names.

## Experimental / gated items to flag in v1.9.x

- `EnvoyProxy.spec.mergeBackends` — experimental, off by default.
- ListenerSet (Gateway API experimental resource) as policy targetRef.
- SDS certificate refs (`enableSDSSecretRef`); Lua (`enableLua`, off by
  default); runtime flags: `EndpointSliceIndex` (default on),
  `PerResourceSystemCASecret` (opt-out), `EnvoyProxyPatch` (default on;
  disable for multi-tenancy).
- Envoy Gateway CRDs all live under `apiVersion:
  gateway.envoyproxy.io/v1alpha1`; Gateway API CRDs consumed from the
  **experimental channel** by default.
