# Traffic Management Recipes — Envoy Gateway v1.9.x

Source root: `site/content/en/latest/` at tag v1.9.2. All extension CRDs
are `apiVersion: gateway.envoyproxy.io/v1alpha1`; core routes are
`apiVersion: gateway.networking.k8s.io/v1` (HTTPRoute, GRPCRoute) unless
noted.

## Baseline facts

- Default managed GatewayClass `controllerName:
  gateway.envoyproxy.io/gatewayclass-controller`; EG manages **a single**
  GatewayClass. `GatewayClass.spec.parametersRef` must point at an
  `EnvoyProxy` resource.
- Gateway address: `export GATEWAY_HOST=$(kubectl get gateway/eg -o
  jsonpath='{.status.addresses[0].value}')`. No-LoadBalancer fallback:
  find svc via selector
  `gateway.envoyproxy.io/owning-gateway-namespace=default,gateway.envoyproxy.io/owning-gateway-name=eg`,
  then `kubectl -n envoy-gateway-system port-forward service/$ENVOY_SERVICE 8888:80`.
- Privileged listener ports (<1024, e.g. 80) are internally remapped to
  unprivileged ports.
- **Gateway API version**: v1.9 reconciles `TCPRoute`/`UDPRoute` via
  `gateway.networking.k8s.io/v1` (promoted in Gateway API v1.6);
  **`v1alpha2` is no longer served in the standard channel**. The task
  docs still show `v1alpha2` in TCPRoute/UDPRoute/TLSRoute examples —
  treat `v1` as the correct apiVersion for TCP/UDP.
- Supported HTTPRoute filters: `RequestHeaderModifier`,
  `ResponseHeaderModifier`, `RequestMirror`, `RequestRedirect`,
  `URLRewrite`, `ExtensionRef`. Only `Service` (+ EG `Backend`, MCS
  `ServiceImport`) backendRef kinds.
- Default Envoy request timeout is **15s**.

## HTTP routing (`tasks/traffic/http-routing.md`)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
spec:
  parentRefs: [{name: eg}]        # sectionName: <listener> to pin a listener
  hostnames: ["foo.example.com"]  # matched before rules
  rules:
    - matches: [{path: {type: PathPrefix, value: /login}},
                {headers: [{name: env, value: canary}]}]
      backendRefs: [{kind: Service, name: foo-svc, port: 8080, weight: 1}]
```

- Unmatched host/path → `404`. Most specific match wins.
- Cookie matching via EG extension `HTTPRouteFilter`:
  ```yaml
  apiVersion: gateway.envoyproxy.io/v1alpha1
  kind: HTTPRouteFilter
  spec:
    matches: [{cookies: [{name: choco, value: chip}]}]
  # referenced from HTTPRoute rule: filters: [{type: ExtensionRef,
  #   extensionRef: {group: gateway.envoyproxy.io, kind: HTTPRouteFilter, name: cookie-match}}]
  ```

## gRPC routing (`tasks/traffic/grpc-routing.md`)

```yaml
kind: GRPCRoute
apiVersion: gateway.networking.k8s.io/v1
spec:
  parentRefs: [{name: example-gateway}]
  hostnames: ["grpc-example.com"]
  rules:
    - matches:
        - method: {service: grpc.reflection.v1alpha.ServerReflection, method: ServerReflectionInfo}
        - method: {method: "Pin.+", service: ".*.Echo", type: RegularExpression}
      backendRefs: [{kind: Service, name: yages, port: 9000}]
```

- gRPC-Web is supported on the same config.
- Streaming RPCs outlive the 15s default → set
  `BackendTrafficPolicy.spec.timeout.http.requestTimeout: 0s` targeting
  the GRPCRoute.

## TCP / UDP routing (`tasks/traffic/tcp-routing.md`, `udp-routing.md`)

```yaml
# Gateway listeners: protocol: TCP, allowedRoutes.kinds: [{kind: TCPRoute}]
apiVersion: gateway.networking.k8s.io/v1   # docs show v1alpha2 — superseded
kind: TCPRoute
spec:
  parentRefs: [{name: tcp-gateway, sectionName: foo}]
  rules:
    - backendRefs: [{name: foo, port: 3001}]
```

- Both are **non-transparent proxies**: backend sees the Envoy instance's
  source IP/port, not the client's.

## TLS routes

```yaml
apiVersion: gateway.networking.k8s.io/v1alpha2   # TLSRoute (matches on SNI)
kind: TLSRoute
spec:
  parentRefs: [{name: eg, sectionName: tls}]     # listener protocol TLS
  rules:
    - backendRefs: [{name: httpbin, port: 443}]
```

- SNI dynamic forward proxy: TLSRoute → EG `Backend` of `type:
  DynamicResolver`; upstream port always 443, TLS passthrough listener
  required, Backend must be the route's only backendRef, loopback SNIs
  denied.

## Traffic splitting (`tasks/traffic/http-traffic-splitting.md`)

- Multiple `backendRefs` split equally; `weight` (default 1) gives
  proportion `weight / Σweights` — not a percentage, need not sum to 100.
- Invalid backendRef → its share returns HTTP `500` (route still serves
  valid backends).

## Redirects (`tasks/traffic/http-redirect.md`)

```yaml
rules:
  - filters:
      - type: RequestRedirect
        requestRedirect:
          scheme: https          # or port/hostname/path
          statusCode: 301
```

- Force-HTTPS pattern: operator-owned redirect HTTPRoute in Gateway
  namespace with `parentRefs[].sectionName: http`, no hostnames (catches
  all), `requestRedirect: {scheme: https, statusCode: 301}`.
- Redirect and URLRewrite filters are mutually exclusive on a rule.

## URL rewrites (`tasks/traffic/http-urlrewrite.md`)

```yaml
filters:
  - type: URLRewrite
    urlRewrite:
      path: {type: ReplacePrefixMatch, replacePrefixMatch: /replace}
      hostname: envoygateway.io
```

Extended rewrites via `HTTPRouteFilter` (also usable from GRPCRoute):

```yaml
spec:
  urlRewrite:
    path:
      type: ReplaceRegexMatch                 # RE2 syntax
      replaceRegexMatch:
        pattern: '^/service/([^/]+)(/.*)$'
        substitution: '\2/instance/\1'
    hostname:
      type: Header                            # or Backend
      header: x-custom-host
    appendXForwardedHost: false               # default true
```

- Rewritten requests expose `X-Envoy-Original-Path`.

## Header manipulation

```yaml
filters:
  - type: RequestHeaderModifier      # ResponseHeaderModifier analogous
    requestHeaderModifier:
      add: [{name: x-a, value: foo}]     # appends if header already present
      set: [{name: x-b, value: bar}]     # replaces
      remove: ["x-c"]
```

- **Early header modification** (before routing/tracing) via
  ClientTrafficPolicy on a Gateway:
  `spec.headers.earlyRequestHeaders.{add,set,remove}`.

## Request mirroring (`tasks/traffic/http-request-mirroring.md`)

```yaml
filters:
  - type: RequestMirror
    requestMirror:
      backendRef: {kind: Service, name: backend-2, port: 3000}
```

- Mirror responses are always ignored; multiple `RequestMirror` filters
  per rule allowed.

## Timeouts

HTTP — native Gateway API field on the rule:

```yaml
rules:
  - timeouts:
      request: "4s"          # total; must be >= backendRequest
      backendRequest: "3s"   # per upstream attempt
```

gRPC — GRPCRoute has **no native `timeouts` field yet** (upstream
gateway-api#3139); use BackendTrafficPolicy targeting the GRPCRoute
(max one BTP per GRPCRoute, else `Conflicted`):

```yaml
spec:
  timeout:
    http:
      requestTimeout: "5s"        # "0s" disables (required for streaming)
      maxStreamDuration: "0s"     # "0s" = streams run indefinitely
      streamIdleTimeout: "1h"
```

- Exceeded unary timeout → gRPC `DEADLINE_EXCEEDED` (HTTP 504).

## Retries (`tasks/traffic/retry.md`)

- Since EG v1.3, core HTTPRoute retries (GEP-1731) are supported; core
  API setting **takes precedence** over BackendTrafficPolicy.

```yaml
kind: BackendTrafficPolicy
spec:
  targetRefs: [{kind: HTTPRoute, name: backend, group: gateway.networking.k8s.io}]
  retry:
    numRetries: 5            # default 2
    perRetry:
      backOff: {baseInterval: 100ms, maxInterval: 10s}
      timeout: 250ms
    retryOn:
      httpStatusCodes: [500]
      triggers: [connect-failure, retriable-status-codes]
      # default triggers: connect-failure, refused-stream, unavailable, cancelled, retriable-status-codes(503)
```

## Circuit breaking (`tasks/traffic/circuit-breaker.md`)

```yaml
spec:
  circuitBreaker:
    maxConnections: 1024        # default 1024 (all four)
    maxPendingRequests: 0
    maxParallelRequests: 10
    maxParallelRetries: 1024
```

- Counters are per-Envoy-process (not synchronized) and **per
  backendRef** even when the policy targets a Gateway. Overflow → fast
  `503`.

## Failover / outlier detection (`tasks/traffic/failover.md`)

- Active/passive: EG `Backend` with `spec.fallback: true` marks the
  passive backend; route lists both as backendRefs; passive health check
  (outlier ejection) via BTP:

```yaml
spec:
  healthCheck:
    passive:
      baseEjectionTime: 10s
      interval: 2s
      maxEjectionPercent: 100
      consecutive5XxErrors: 1
```

- Active health checking (HTTP/TCP) also exists as `healthCheck.active`.

## Load balancing (`tasks/traffic/load-balancing.md`, `zone-aware-routing.md`)

```yaml
spec:
  loadBalancer:
    type: RoundRobin | Random | LeastRequest | ConsistentHash | BackendUtilization
    consistentHash:
      type: SourceIP | Header | Cookie        # Maglev hash
      header: {name: FooBar}
      cookie: {name: FooBar, ttl: 60s}
    slowStart: {...}                           # RR, LeastRequest, BackendUtilization only
```

Zone-aware routing (`loadBalancer.zoneAware`), precedence:
BackendTrafficPolicy > Service-level (`trafficDistribution: PreferClose`):

```yaml
zoneAware:
  preferLocal:                       # XOR weightedZones
    minEndpointsThreshold: 1
    force:
      minEndpointsInZoneThreshold: 1
```

Support matrix — `preferLocal`: RoundRobin/LeastRequest/Random only;
`weightedZones`: all except DynamicModule. Nodes need
`topology.kubernetes.io/zone` labels, ≥2 zones.

## Session persistence (`tasks/traffic/session-persistence.md`)

```yaml
rules:
  - sessionPersistence:
      sessionName: Session-A
      type: Cookie                  # or Header
      absoluteTimeout: 10s
      cookieConfig:
        lifetimeType: Permanent     # or Session
```

## Local rate limiting (`tasks/traffic/local-rate-limit.md`)

```yaml
spec:
  rateLimit:
    local:
      rules:
        - clientSelectors:          # omit entirely = limit all requests
            - headers: [{name: x-user-id, value: one}]
            - path: {type: Exact, value: /api/users}
            - methods: [{value: POST}]
          limit:
            requests: 3
            unit: Hour              # Second|Minute|Hour|Day|Week|Month|Year
```

- Enforced **per Envoy replica** (2 replicas × 10 r/s limit = 20 r/s
  total). Limit bucket is **per route** even when targeting a Gateway.
  Over-limit → `429`.
- **`distinct` header matching NOT supported locally** — use global.

## Global rate limiting (`tasks/traffic/global-rate-limit.md`)

Same `rules` shape under `rateLimit.global`; extras:

- `headers: [{type: Distinct, name: x-user-id}]` → per-value buckets;
  `sourceCIDR: {value: 0.0.0.0/0, type: Distinct|Exact}`.
- `shared: true` on a rule = bucket shared across all routes (default is
  per-route).
- Shared across all Envoy replicas; requires Redis (Envoy Ratelimit
  service). Enable in the `EnvoyGateway` config (ConfigMap
  `envoy-gateway-config` in `envoy-gateway-system`):

```yaml
rateLimit:
  backend:
    type: Redis
    redis:
      url: redis.redis-system.svc.cluster.local:6379
```

Helm: `helm upgrade eg oci://docker.io/envoyproxy/gateway-helm --set
config.envoyGateway.rateLimit.backend.type=Redis --set
config.envoyGateway.rateLimit.backend.redis.url="redis...:6379"
--reuse-values -n envoy-gateway-system`

- Controller-spun-up rate-limit deployment tunable via
  `EnvoyGateway.provider.kubernetes.rateLimitDeployment`:
  `replicas` (default 1), `container.image`, `container.resources`.

## Bandwidth limit (`tasks/traffic/bandwidth-limit.md`)

```yaml
spec:
  bandwidthLimit:                 # at least one of request/response
    request:  {limit: {value: "10Ki", unit: Second}}
    response:
      limit: {value: "1Mi", unit: Second}
```

- Throttles (pauses transfer) rather than rejecting; enforced per Envoy
  instance, per route.

## Connection limit (`tasks/traffic/connection-limit.md`)

```yaml
kind: ClientTrafficPolicy
spec:
  targetRefs: [{kind: Gateway, name: eg, group: gateway.networking.k8s.io}]
  connection:
    connectionLimit: {value: 5}
```

- Counters not synchronized across proxies.

## Request buffering (`tasks/traffic/request-buffering.md`)

```yaml
spec:
  requestBuffer:
    limit: 4        # bytes; SI suffixes supported (4Ki, 1Mi)
```

- Over-limit → `413`. **Warning:** incompatible with streaming/upgrade
  traffic (gRPC streaming, WebSocket) — requests can hang.

## Fault injection (`tasks/traffic/fault-injection.md`)

```yaml
spec:
  faultInjection:
    abort:
      httpStatus: 501     # or grpcStatus: 14 (for GRPCRoute targets)
      percentage: 50      # default 100
    delay:
      fixedDelay: 2s
```

## Direct response (`tasks/traffic/direct-response.md`)

Via `HTTPRouteFilter` + `ExtensionRef`:

```yaml
spec:
  directResponse:
    contentType: text/plain
    statusCode: 503
    body:
      type: Inline                        # or ValueRef (ConfigMap key `response.body`)
      inline: "Oops! Your request is not found."
```

- Body capped at **4096 bytes**.

## Response override (`tasks/traffic/response-override.md`)

```yaml
spec:
  responseOverride:
    - match:
        statusCodes:
          - {type: Value, value: 500}
          - {type: Range, range: {start: 501, end: 511}}
      source: All | Backend | Local  # Local = only Envoy-generated (401 JWT, 429 RL)
      response:                      # or redirect: {...}
        contentType: application/json
        body: {type: Inline, inline: '...'}
```

## Response compression (`tasks/traffic/response-compression.md`)

```yaml
spec:
  compressor:                       # `compression` field is DEPRECATED
    - type: Brotli
      brotli: {}
    - {type: Gzip, gzip: {}}
    - {type: Zstd, zstd: {}}
      minContentLength: 1024
```

- Selection by client `Accept-Encoding` q-values. Strong `ETag`s
  stripped on compression.

## HTTP/3 (`tasks/traffic/http3.md`)

```yaml
kind: ClientTrafficPolicy
spec:
  http3: {}
  targetRefs: [{kind: Gateway, name: eg, group: gateway.networking.k8s.io}]
```

- Requires an HTTPS listener (TLS secret). Testing needs a real external
  LB — Kubernetes cannot port-forward UDP (kubernetes/kubernetes#47862).

## HTTP CONNECT tunnels (`tasks/traffic/http-connect-tunnels.md`)

```yaml
kind: BackendTrafficPolicy
spec:
  targetRef: {kind: Gateway, name: connect-proxy, group: gateway.networking.k8s.io}
  httpUpgrade:
    - type: CONNECT
```

- API note: `httpUpgrade` defaults to websocket if unset; ignored when
  `requestBuffer` is set.

## Backend resource + routing outside Kubernetes

`Backend` is **disabled by default** — enable via EnvoyGateway config
`extensionApis.enableBackend: true`. Security warning:
CVE-2021-25740-style misuse (loopback/localhost forbidden by default;
`DynamicResolver` can reach anything — restrict via RBAC and
SecurityPolicy authorization).

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: Backend
spec:
  endpoints:
    - fqdn: {hostname: httpbin.org, port: 80}
---
spec:
  type: DynamicResolver                            # resolves request Host
  tls:
    wellKnownCACertificates: System
```

- Referenced as `backendRefs: [{group: gateway.envoyproxy.io, kind:
  Backend, name: httpbin}]`. Supports BackendTLSPolicy attachment.
- Alternative without Backend: selector-less `Service` + `EndpointSlice`
  with `addressType: FQDN`.

## Multicluster service (`tasks/traffic/multicluster-service.md`)

- MCS `ServiceImport` usable directly as HTTPRoute backendRef; requires
  ReferenceGrant in the ServiceImport namespace.

## Host header normalization (`tasks/traffic/host-header-normalization.md`)

```yaml
kind: ClientTrafficPolicy
spec:
  headers:
    host:
      stripTrailingHostDot: true    # `example.com.:443` → `example.com:443`
```

- Without it, `Host: example.com.` never matches routes for
  `example.com` (unlike NGINX).

## Gateway address customization (`tasks/traffic/gateway-address.md`)

- `Gateway.spec.addresses` → External IPs of the Envoy Service: address
  must be `type: IPAddress` and ServiceType `LoadBalancer` or `NodePort`
  (EG default is LoadBalancer). If explicitly set, `spec.addresses` is
  the **only** source populating Gateway status addresses.
- With ServiceType `ClusterIP`, addresses become the Cluster IP.
