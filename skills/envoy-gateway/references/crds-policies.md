# CRD & Gateway-API Surface — Envoy Gateway v1.9.2

Sources: `api/extension_types.md`, `api/gateway_api/*.md`,
`concepts/gateway_api_extensions/*.md`,
`concepts/{gateway-api,api-gateways,proxy,load-balancing,rate-limiting}.md`,
`tasks/traffic/gatewayapi-support.md`. (The support-matrix doc lives at
`tasks/traffic/gatewayapi-support.md` in v1.9.2; it moves to `concepts/`
post-1.9.)

## Gateway API (sig-network) version & conformance

- **Supported Gateway API version: v1.6** — repo go.mod pins
  `sigs.k8s.io/gateway-api v1.6.1`.
- **v1.9 upgrade caveat** (warning in `install/install-helm.md`): this
  release reconciles **TCPRoute and UDPRoute via
  `gateway.networking.k8s.io/v1`** (promoted in Gateway API v1.6).
  Upgrade Gateway API CRDs to v1.6 **before** upgrading Envoy Gateway,
  else TCP/UDP routes are silently skipped. Standard channel no longer
  serves `v1alpha2`. Experimental channel serves both `v1` and `v1alpha2`.
  Storage-version migration:
  ```shell
  kubectl get tcproutes.gateway.networking.k8s.io -A -o json | kubectl replace -f -
  kubectl get udproutes.gateway.networking.k8s.io -A -o json | kubectl replace -f -
  ```
- Channel/GA status of supported upstream resources: GatewayClass GA
  (cluster-scoped), Gateway GA, HTTPRoute GA (rule `name`/sectionName
  Experimental since v1.2.0), GRPCRoute GA since v1.1.0, BackendTLSPolicy
  GA since v1.4.0, ReferenceGrant GA since v0.6.0 (CORE conformance for
  cross-namespace refs).
- **ListenerSet** is an *experimental* Gateway API resource (group
  `gateway.networking.x-k8s.io`), opt-in via `EnvoyGateway.gatewayAPI`
  settings.

## Supported Gateway API resources & EG-specific limits

From `tasks/traffic/gatewayapi-support.md`:

- **GatewayClass**: EG manages **a single** GatewayClass matching its
  configured `controllerName` (default
  `gateway.envoyproxy.io/gatewayclass-controller`, settable via
  `EnvoyGateway.gateway.controllerName`). `parametersRef`, if specified,
  **must** point to an **EnvoyProxy** resource.
- **Gateway**: creating a Gateway referencing the managed class spawns a
  managed Envoy Proxy deployment (1 Gateway → 1 Envoy fleet, unless
  `EnvoyProxy.spec.mergeGateways: true` merges all Gateways in the class
  onto one infra — then listener port/protocol/hostname tuples must be
  unique; duplicate listeners rejected `Accepted=False`).
- **HTTPRoute** supported filters: `requestHeaderModifier`,
  `responseHeaderModifier`, `requestMirror`, `requestRedirect`,
  `urlRewrite`, `extensionRef` (EG extended filters). BackendRef filters
  limited to `requestHeaderModifier`/`responseHeaderModifier` in
  `HTTPBackendRef`.
- **GRPCRoute** filters: `requestHeaderModifier`,
  `responseHeaderModifier`, `requestMirror`, `extensionRef` referencing
  an **HTTPRouteFilter**. Only header-modifier filters inside
  `GRPCBackendRef`.
- **TCPRoute / UDPRoute**: port-based forwarding; **non-transparent
  proxying only** — backend sees Envoy's source IP/port, not the
  client's.
- **TLSRoute**: TCP routing matched on TLS metadata (SNI).
- **BackendRef kind: `Service` only.** Routing to arbitrary URLs or other
  kinds is not supported natively (custom backend kinds possible via
  Extension Server `backendResources`). EG `Backend` requires
  `enableBackend`.
- **ReferenceGrant** supported uses: xRoute → Service cross-namespace;
  HTTPRoute `requestMirror` backendRef cross-namespace; Gateway
  `SecretObjectReference` (listener cert) cross-namespace.
- **BackendTLSPolicy**: Direct PolicyAttachment without
  defaults/overrides, must reside in the **same namespace as the target
  Service**; no cross-namespace cert refs. Spec: `targetRefs`,
  `validation.{hostname (SNI; no IPs, no wildcards), subjectAltNames (max
  5), caCertificateRefs XOR wellKnownCACertificates ("System"), options}`.
  When attached to an EG `Backend`, its `validation.hostname` takes
  precedence over `Backend.spec.tls.sni`.

## Envoy Gateway CRD inventory

Group `gateway.envoyproxy.io/v1alpha1`, all namespaced-scope. Exactly
**9 resource types**:

| Kind | Role | Key spec fields |
|---|---|---|
| `EnvoyProxy` | Data-plane config; attached via `GatewayClass.spec.parametersRef` or `Gateway.spec.infrastructure.parametersRef` | `provider.kubernetes` (`envoyDeployment`, `envoyDaemonSet`, `envoyService`, `envoyHpa`, `envoyPDB`, `envoyServiceAccount`), `logging`, `telemetry`, `bootstrap`, `concurrency`, `routingType` (`Endpoint` default / `Service` ClusterIP), `extraArgs`, `mergeGateways`, `mergeBackends`, `shutdown`, `filterOrder`, `backendTLS`, `ipFamily`, `preserveRouteOrder`, `luaValidation`, `dynamicModules`, `geoIP`, `mergeType` |
| `Backend` | Custom endpoints + connection settings; referenced from route `backendRefs`; **off by default** (`extensionApis.enableBackend`) | `type` (`Endpoints` default / `DynamicResolver`), `endpoints[]` (each: `fqdn` / `ip` / `unix`, optional `hostname`, `zone`), `appProtocols[]`, `fallback`, `tls` (`caCertificateRefs` XOR `wellKnownCACertificates`, `insecureSkipVerify`, `sni`, `autoSNIFromEndpointHostname`; merged with BackendTLSPolicy — policy wins) |
| `ClientTrafficPolicy` | Downstream client ↔ Envoy listener | targeting + `tcpKeepalive`, `proxyProtocol`, `clientIPDetection` (exactly one of `xForwardedFor`/`customHeader`/`directSourceIP`), `tls` (incl. mTLS `clientValidation`), `path`, `headers`, `timeout`, `connection`, `http1`/`http2`/`http3`/`grpc`, `healthCheck`, `scheme` |
| `BackendTrafficPolicy` | Envoy listener ↔ backend | targeting + `loadBalancer` (default `LeastRequest`), `retry`, `proxyProtocol`, `tcpKeepalive`, `healthCheck`, `circuitBreaker`, `timeout`, `connection`, `dns`, `http2`, `rateLimit` (`global` and/or `local`), `bandwidthLimit`, `faultInjection`, `admissionControl`, `useClientProtocol`, `compressor`, `responseOverride[]`, `httpUpgrade`, `requestBuffer`, `telemetry`, `routingType`, `mergeType` |
| `SecurityPolicy` | Authn/authz at the edge | targeting + `jwt`, `oidc`, `apiKeyAuth`, `basicAuth`, `extAuth`, `authorization`, `cors`, `csrf`, `mergeType` |
| `EnvoyExtensionPolicy` | Extensibility hooks into the filter chain | targeting + `wasm[]`, `extProc[]`, `lua[]` (**off by default** — `extensionApis.enableLua`), `dynamicModule[]`, `mergeType` |
| `HTTPRouteFilter` | Extended filter referenced by HTTPRoute/GRPCRoute `extensionRef` | `urlRewrite`, `directResponse`, `credentialInjection`, `matches[]` (extra matchers, e.g. `cookies[]`; ANDed with rule matches) |
| `EnvoyPatchPolicy` | JSONPatch (RFC 6902) directly onto generated xDS | `type: JSONPatch`, `jsonPatches[]`, `targetRef` (Gateway by default; GatewayClass when `mergeGateways`; same-namespace only), `priority` (applied ascending). ⚠ Must be enabled via `extensionApis.enableEnvoyPatchPolicy` — "may lead to complete security compromise" |
| `EnvoyGateway` | **Control-plane config file** (not a per-gateway CRD; rendered via Helm `config.envoyGateway`) | `gateway.controllerName`, `provider`, `logging`, `admin`, `telemetry`, `xdsServer`, `rateLimit`, `extensionManager(s)`, `extensionApis`, `gatewayAPI`, `runtimeFlags`, `envoyProxy` (fleet-wide default EnvoyProxySpec) |

## Policy attachment model (targetRef / sectionName / precedence)

- **Targeting fields** (shared on ClientTrafficPolicy,
  BackendTrafficPolicy, SecurityPolicy, EnvoyExtensionPolicy):
  - `targetRef` (singular) — **DEPRECATED**, use
    `targetRefs`/`targetSelectors`.
  - `targetRefs[]` — `sectionName` selects one listener (on
    Gateway/ListenerSet) or one **named route rule** (on xRoute).
  - `targetSelectors[]` — label-selector-based targeting.
  - Policies are **same-namespace only**. No cross-namespace attachment.
- **Attachable kinds**:
  - ClientTrafficPolicy: `Gateway`, `ListenerSet` (only).
  - BackendTrafficPolicy: `Gateway`, `ListenerSet`, `HTTPRoute`,
    `GRPCRoute`, `TCPRoute`, `UDPRoute`, `TLSRoute`.
  - SecurityPolicy: `Gateway`, `ListenerSet`, `HTTPRoute`, `GRPCRoute`,
    `TCPRoute` — TCPRoute limited to **client-IP CIDR authorization
    only**.
- **Precedence (direct, non-merged)** — most specific wins:
  1. Route rule-level (xRoute + `sectionName` → named rule)
  2. Route-level (xRoute, no sectionName)
  3. ListenerSet listener-level → ListenerSet-level → parent
     Gateway-level; or Gateway listener-level → Gateway-level.
  - Gateway listeners and ListenerSet listeners are **sibling scopes**:
    a Gateway listener-level policy never applies to
    ListenerSet-attached routes and vice versa.
  - Overridden policies get status condition `Overridden=True`.
- **Same-level tie-break**: oldest `creationTimestamp` wins; identical
  timestamps → alphabetical by namespaced name.
- **Merging (`mergeType`)**: `StrategicMerge` | `JSONMerge` | `Replace`.
  Only settable on policies targeting **xRoute** resources (not
  Gateway/ListenerSet). Unset → no merging, most specific policy wins.
  Route policy merges into the *closest parent* policy. For
  SecurityPolicy merges, secret/backend refs resolve against the
  namespace of the policy that originally defined the field.
- **EnvoyProxy config hierarchy** (highest→lowest): Gateway-level >
  GatewayClass-level > `EnvoyGateway.envoyProxy` default spec.
  More-specific EnvoyProxy **replaces** less-specific unless its
  `spec.mergeType` requests a merge.

## Extension Server (control-plane extensibility)

- Configured in `EnvoyGateway.extensionManager` (singular) or
  `extensionManagers[]` (chained; unique `name`; mutually exclusive).
  ⚠ Same "complete security compromise" warning as EnvoyPatchPolicy.
- Fields: `resources[]` (GVKs as **route filter** resources),
  `policyResources[]` (GVKs as **directly attached policies**),
  `backendResources[]` (GVKs usable as custom `backendRef` kinds),
  `hooks.xdsTranslator` (`pre[]`/`post[]`), `service` (endpoint:
  `fqdn`/`ip`/`unix`; retry: maxAttempts 4, retryable codes
  `["UNAVAILABLE"]`), `failOpen` (default **false** — hook errors skip
  the xDS update and preserve previous state), `maxMessageSize` (4M).
- **Wasm** (EnvoyExtensionPolicy): runtime fixed to **v8**; code source
  `HTTP` (url + sha256) or `Image` (OCI, pulled by EG); `rootID`
  required; `failOpen` default false.
- **DynamicModule**: modules must be allowlisted in
  `EnvoyProxy.spec.dynamicModules`.

## xDS translation architecture (summary)

- Control plane (Envoy Gateway) watches Kubernetes Gateway API + EG
  extension CRDs, translates them into xDS, and provisions/updates Envoy
  instances (Deployment by default; DaemonSet opt-in via EnvoyProxy).
- Pipeline: k8s resources → **gateway-api translator** → **IR**
  (intermediate representation) → **xds-translator runner** (Extension
  Server pre/post hooks fire here) → xDS snapshot → **xds-server**
  (gRPC; default max receive 32MiB, connection age randomized 10–12h) →
  Envoy.
- Local translation CLI: `egctl x translate --from gateway-api --to
  gateway-api|ir|xds -f <file-or--->`; `-t` filters xDS output to
  resource types. Recommended for iterating on
  `EnvoyProxy.spec.bootstrap` overrides.
- Default Envoy HTTP filter chain order (override via EnvoyProxy
  `filterOrder`): `custom_response → health_check → fault → cors →
  header_mutation → ext_authz → api_key_auth → basic_auth → oauth2 →
  jwt_authn → stateful_session → buffer → lua → ext_proc → wasm →
  dynamic_modules → geoip → rbac → local_ratelimit → ratelimit →
  bandwidth_limit → grpc_web → grpc_stats → credential_injector →
  compressor → dynamic_forward_proxy → router` (router always last).

## Load balancing & rate limiting specifics

- `BackendTrafficPolicy.spec.loadBalancer.type` ∈ `RoundRobin`,
  `Random`, `LeastRequest` (**default**), `ConsistentHash`,
  `BackendUtilization` (ORCA load feedback). EG **strips ORCA headers by
  default** when BackendUtilization is on —
  `backendUtilization.keepResponseHeaders: true` to forward. `slowStart`
  for RoundRobin/LeastRequest/BackendUtilization; `zoneAware`.
- Rate limiting via `BackendTrafficPolicy.spec.rateLimit.{global,local}`.
  **Limits are per-route even when the policy targets a Gateway**
  (Gateway with 3 routes and limit 100r/s → each route gets its own
  100r/s bucket). Global RL uses an EG-deployed Rate Limit Service
  backed by Redis. Local RL is per-Envoy-instance. When both are set:
  **local is evaluated first, then global**.

## Experimental / deprecated / not-supported flags (v1.9.2)

- **Experimental/opt-in**: ListenerSet; Lua (`enableLua`);
  EnvoyPatchPolicy (`enableEnvoyPatchPolicy`); Extension Manager;
  Backend CRD (`enableBackend`); `EnvoyProxy.spec.mergeBackends`;
  SDS cert refs (`enableSDSSecretRef`).
- **Deprecated**: `targetRef` (singular) → `targetRefs`/`targetSelectors`;
  `ClientTrafficPolicy.enableProxyProtocol` → `proxyProtocol`;
  `BackendTrafficPolicy.compression` → `compressor`; `RateLimitSpec.type`
  → set `global`/`local` directly.
- **Not supported**: non-Service backendRefs (native); arbitrary URL
  routing; cross-namespace policy attachment; per-`HTTPBackendRef`
  filters other than header modifiers; transparent TCP/UDP proxying;
  TCPRoute with SecurityPolicy features other than CIDR authz;
  configurable Wasm runtime (v8 only); ExternalName services
  ("SHOULD NOT support", CVE-2021-25740).
