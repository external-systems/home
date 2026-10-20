# Security Recipes — Envoy Gateway v1.9.2

Source root: `site/content/en/latest` at tag v1.9.2. All Envoy Gateway
extension CRDs are `apiVersion: gateway.envoyproxy.io/v1alpha1`.
Gateway API resources are `gateway.networking.k8s.io/v1` (v1beta1 for
ReferenceGrant, v1alpha3 for BackendTLSPolicy).

Common test pattern: `export GATEWAY_HOST=$(kubectl get gateway/eg -o
jsonpath='{.status.addresses[0].value}')`, or port-forward the managed
Envoy Service:

```sh
export ENVOY_SERVICE=$(kubectl get svc -n envoy-gateway-system \
  --selector=gateway.envoyproxy.io/owning-gateway-namespace=default,gateway.envoyproxy.io/owning-gateway-name=eg \
  -o jsonpath='{.items[0].metadata.name}')
kubectl -n envoy-gateway-system port-forward service/${ENVOY_SERVICE} 8443:443 &
```

## SecurityPolicy CRD overview

- `kind: SecurityPolicy`, `gateway.envoyproxy.io/v1alpha1`. Spec fields
  (all optional): `targetRefs`, `targetSelectors`, `mergeType`,
  `apiKeyAuth`, `cors`, `csrf`, `basicAuth`, `jwt`, `oidc`, `extAuth`,
  `authorization`.
- Targets: `Gateway` (+`sectionName` for a listener), `ListenerSet`,
  `HTTPRoute`, `GRPCRoute` (both +`sectionName` for named rules),
  `TCPRoute`. **TCPRoute targets only honor `authorization` rules with
  `principal.clientCIDRs`** — JWT/APIKey/BasicAuth/OIDC/extAuth/GeoIP
  not applicable.
- Policy and target must be in the same namespace.
- Precedence (most specific wins): route rule-level > route-level >
  ListenerSet listener > ListenerSet > Gateway listener-level >
  Gateway-level. Ties: oldest `creationTimestamp`, then alphabetical.
  Less-specific policy shows `Overridden=True`.
- `mergeType: StrategicMerge | JSONMerge` — only on child (route)
  policies; merges with closest parent policy. Same feature in both →
  child wins for that feature.

## TLS termination — HTTPS (`tasks/security/secure-gateways.md`)

- HTTPS listener: `protocol: HTTPS`, `port: 443`, `tls.mode: Terminate`,
  `tls.certificateRefs: [{kind: Secret, group: "", name: example-cert}]`
  (Secret `kubernetes.io/tls`).
- **OCSP stapling**: automatic if the cert Secret contains data field
  `tls.ocsp-staple`.
- Multiple certs on one listener: append to `certificateRefs` —
  supports **RSA+ECDSA dual-stack** and **SNI-based cert selection**.
  Caveat: Gateway API allows multiple `certificateRefs`, but **Envoy
  Gateway only uses one**.
- Cross-namespace cert ref requires `ReferenceGrant` in the target
  namespace. Missing grant → listener `Ready: False`.
- **TLS param customization** (min version, ciphers):
  `ClientTrafficPolicy.spec.tls.minVersion: "1.3"` targeting the Gateway.

## TLS termination — TCP / TLSRoute (`tasks/security/tls-termination.md`)

- `TLS` listener with `tls.mode: Terminate` forwards decrypted bytes to
  backend over plain TCP.
  - TCPRoute: no SNI matching → one backend per listener.
  - TLSRoute: SNI fan-out on one listener. Listener cert must cover
    every route hostname; route hostnames must match listener hostname
    pattern or the route is rejected.
- **SDS certificate references** (external Secret Discovery Service):
  Secret `type: gateway.envoyproxy.io/sds` with `stringData.url:
  unix:///path/socket` and `stringData.secretName: <name>`. **Disabled
  by default** — `extensionApis.enableSDSSecretRef: true` + control-plane
  restart. Socket dir must be mounted into the Envoy pod via
  `envoyDeployment.patch`. SDS certs are opaque → affected listeners
  default to **HTTP/1.1** when sharing a port (condition
  `TLSCertificateNamesUnknown=True`, reason `SDSCertificateOpaque`).

## TLS passthrough (`tasks/security/tls-passthrough.md`)

- `TLS` listener with `tls.mode: Passthrough` (no certificateRefs),
  `hostname` set; app terminates TLS itself. Gateway SNI-routes
  still-encrypted bytes via TLSRoute.

## cert-manager integration (`tasks/security/tls-cert-manager.md`)

- Install cert-manager with Gateway API support:
  `helm install cert-manager jetstack/cert-manager --version v1.17.0 -n
  cert-manager --create-namespace --set config.enableGatewayAPI=true`
  (via ControllerConfiguration). Gateway API CRDs must exist before
  cert-manager starts (or restart it).
- Gateway annotations (gateway-shim): `cert-manager.io/cluster-issuer:
  <name>` (or `cert-manager.io/issuer`), `cert-manager.io/common-name`,
  `cert-manager.io/revision-history-limit`.
- Requirements on the listener: `tls.mode: Terminate`, non-empty
  `hostname`, `certificateRefs` naming the Secret cert-manager will
  create/rotate. EG picks up Secret changes and reloads Envoy
  automatically.
- ACME HTTP-01: ClusterIssuer with
  `spec.acme.solvers: [{http01: {gatewayHTTPRoute: {parentRefs: [{kind:
  Gateway, name: eg, namespace: default}]}}}]` — cert-manager creates a
  temp HTTPRoute for the challenge.
- Debug: `kubectl get certificate/certificaterequest/order/challenge -A`;
  Gateway condition `ResolvedRefs=False` reason `InvalidCertificateRef`.
- ExternalDNS sources: `gateway-httproute`, `gateway-grpcroute`,
  `gateway-tcproute`, `gateway-tlsroute`, `gateway-udproute`.

## Mutual TLS — client cert validation (`tasks/security/mutual-tls.md`)

Terminating HTTPS listener + ClientTrafficPolicy:

```yaml
spec:
  targetRefs: [{group: gateway.networking.k8s.io, kind: Gateway, name: eg}]
  tls:
    clientValidation:
      caCertificateRefs: [{kind: Secret, group: "", name: example-ca-cert}]  # key ca.crt
```

- Validation `mode`: `Request`/`RequireAny`/`VerifyIfGiven`/
  `RequireAndVerify` (default).

## Backend TLS (`tasks/security/backend-tls.md`)

Gateway-API `BackendTLSPolicy` (`gateway.networking.k8s.io/v1alpha3`):

```yaml
spec:
  targetRefs: [{group: "", kind: Service, name: tls-backend, sectionName: https}]  # sectionName = Service port NAME
  validation:
    caCertificateRefs: [{name: example-ca, group: "", kind: ConfigMap}]  # or kind: ClusterTrustBundle
    hostname: www.example.com   # must match a DNS SAN on backend cert
```

- If the target is a `Backend` resource, `sectionName` is the **port
  number** (string), not a name.
- Backend cert must contain a DNS SAN for the validation hostname.
- Customize upstream TLS params globally:
  `EnvoyProxy.spec.backendTLS.minVersion: "1.3"`.

## Backend mTLS (`tasks/security/backend-mtls.md`)

Builds on BackendTLSPolicy for server validation; adds client
certificate two ways:

1. Global: `EnvoyProxy.spec.backendTLS.clientCertificateRef` (Secret
   type `kubernetes.io/tls`).
2. Per-backend: `Backend` CR (**requires `extensionApis.enableBackend:
   true`** + control-plane restart):

```yaml
spec:
  endpoints: [{fqdn: {hostname: tls-backend.default.svc.cluster.local, port: 443}}]
  tls:
    clientCertificateRef: {kind: Secret, name: example-client-cert}
    caCertificateRefs: [{group: "", kind: ConfigMap, name: example-ca}]
```

- `Backend.spec.tls` settings take precedence over
  `EnvoyProxy.backendTLS`.

## Backend skip TLS verification (`tasks/security/backend-skip-tls-verification.md`)

- `Backend.spec.tls.insecureSkipVerify: true` (requires
  `enableBackend: true`). MITM risk, dev/test only. Without a
  BackendTLSPolicy or skip-verify, a TLS backend returns `400 Bad
  Request`.

## CORS (`tasks/security/cors.md`)

Two mechanisms:

1. `SecurityPolicy.spec.cors`: `allowOrigins` (exact, wildcard prefix
   `http://*.foo.com`, or `*`), `allowCredentials`, `allowMethods`,
   `allowHeaders`, `exposeHeaders`.
2. Gateway API `HTTPCORSFilter` in HTTPRoute rule:
   `filters: [{type: CORS, cors: {...}}]`.

Caveats: the CORS filter only answers preflight (OPTIONS); it never
denies requests — browsers enforce. The route must match OPTIONS
requests or the filter isn't invoked. Origin matching includes port.

## CSRF (`tasks/security/csrf.md`)

- `SecurityPolicy.spec.csrf`. Validates `Origin` on mutating methods
  (POST/PUT/DELETE/PATCH); GET/HEAD/OPTIONS unaffected. Fields:
  `additionalOrigins` and `shadowFraction: {numerator,
  denominator=100}`.
- Scheme is ignored (host+port comparison only). Wildcard
  `https://*.trusted.com` matches subdomains, not apex. Rejection = 403.
- `shadowFraction.numerator: 100` = full dry-run with metrics
  `request_valid`/`request_invalid`; doubles as gradual-rollout knob;
  default 0 (enforce all).

## Basic auth (`tasks/security/basic-auth.md`)

- `SecurityPolicy.spec.basicAuth.users: {name: <secret>}`. Secret:
  Opaque, key `.htpasswd`, htpasswd format. **Only SHA hash supported.**
  Returns `401`. HTTPS-only urged.

## API key auth (`tasks/security/apikey-auth.md`)

- `SecurityPolicy.spec.apiKeyAuth`: `credentialRefs: [{group: "", kind:
  Secret, name: ...}]` (Opaque Secret; each key = client ID, value = API
  key) + `extractFrom: [{headers: [x-api-key]}]`.
- **Gotcha**: value from the `Authorization` header is compared
  verbatim — Secret value must NOT include the `Bearer ` prefix (clients
  still send `Authorization: Bearer <key>`). Failure = 401.
- v1.9: `extractFrom` stricter — ≥1 entry, exactly one of
  headers/params/cookies per entry, non-empty names.

## JWT authentication (`tasks/security/jwt-authentication.md`)

- `SecurityPolicy.spec.jwt.providers[]`: `name`, `issuer`, `remoteJWKS.uri`
  or `localJWKS: {type: ValueRef, valueRef: {group: "", kind: ConfigMap,
  name: ...}}` (ConfigMap key `jwks`). Attach to HTTPRoute or GRPCRoute.
  Failure: 401 (HTTP) / `Unauthenticated` (gRPC).
- Remote JWKS with self-signed/external host: `remoteJWKS.backendRefs` →
  `Backend` resource + `BackendTLSPolicy` for the JWKS CA;
  `backendSettings` currently supports only `retry`.
- v1.9: JWT `failOpen` (→ Envoy `allow_missing_or_failed`) and
  `failedRefetchDuration` (default 1s).

## JWT claim authorization (`tasks/security/jwt-claim-authorization.md`)

- Requires `jwt` in the same SecurityPolicy:
  `spec.authorization: {defaultAction: Deny, rules: [{name, action:
  Allow, principal: {jwt: {provider: example, scopes: [...], claims:
  [{name: user.name, values: [...]}]}}}]}`. Failure = 403. `scopes`
  matches the space-delimited `scope` claim.

## Header/method authorization (`tasks/security/http-header-method-auth.md`)

- `SecurityPolicy.spec.authorization` rules (not authn):
  `principal: {headers: [{name: x-user-id, values: [...]}]}`;
  `operation: {methods: [GET, POST]}`. Conditions ANDed within a rule;
  rules evaluated in order; non-matching → `defaultAction`.
- v1.9: CEL expressions + path matching in authorization rules.

## OIDC (`tasks/security/oidc.md`)

- `SecurityPolicy.spec.oidc`: `provider.issuer`, `clientID`,
  `clientSecret: {name: <secret>}` (Opaque Secret, key `client-secret`),
  `redirectURL`, `logoutPath`, optional `cookieDomain`,
  `cookieNames.accessToken`, `scopes`.
- Redirect URL must be HTTPS. **`redirectURL` and `logoutPath` must
  match the target HTTPRoute** or the OAuth2 filter never sees the
  callback.
- Gateway-level OIDC protects all attached HTTPRoutes; set
  `cookieDomain` to the root domain to share token cookies across
  subdomains.
- Self-signed IdP: `provider.backendRefs` → `Backend` +
  `BackendTLSPolicy`; explicit `authorizationEndpoint`/`tokenEndpoint`.
- v1.9.1: session cookies AES-256-GCM (CVE-2026-47775); HTTP no longer
  allowed as OIDC issuer URL scheme.

## External authorization (`tasks/security/ext-auth.md`)

- `SecurityPolicy.spec.extAuth.http: {backendRefs: [{name:
  http-ext-auth, port: 9002}], headersToBackend: ["x-current-user"]}` or
  `extAuth.grpc: {backendRefs: [...]}`. Unauthorized → 403.
  `headersToBackend` forwards auth-service response headers to the
  backend.
- TLS to the auth service via `BackendTLSPolicy` targeting the auth
  Service.

## IP allow/deny (`tasks/security/restrict-ip-access.md`)

- `authorization.rules[].principal.clientCIDRs: [10.0.1.0/24]` with
  `defaultAction: Deny` (allowlist) or `Allow` (denylist). Works on
  Gateway/HTTPRoute/GRPCRoute/**TCPRoute**.
- Uses original source IP: pair with
  `ClientTrafficPolicy.spec.clientIPDetection` — `xForwardedFor:
  {numTrustedHops: 1}`. Deny response body: `RBAC: access denied`.

## GeoIP authorization (`tasks/security/geoip-authorization.md`)

Requires three pieces:

1. `EnvoyProxy.spec.geoIP.provider: {type: MaxMind, maxMind: {...}}` —
   local MaxMind `.mmdb` file mounted into the proxy container.
2. `ClientTrafficPolicy.spec.clientIPDetection`: one of
   `xForwardedFor.numTrustedHops`, `customHeader`, or `directSourceIP`
   (L4-transparent LB + `externalTrafficPolicy: Local`).
3. The SecurityPolicy itself:
   `authorization.rules[].principal.clientIPGeoLocations`.

## Credential injection (`tasks/security/credential-injection.md`)

`HTTPRouteFilter` CR:

```yaml
spec:
  credentialInjection:
    overwrite: true           # default: don't overwrite existing header
    header: <name>            # optional; default Authorization
    credential:
      valueRef: {name: jwt-credential}   # Secret with field named `credential`
```

- Reference from HTTPRoute rule `filters` (ExtensionRef) or from a
  **BackendRef's** `filters` (per-backend injection). GRPCRoute:
  `extensionRef` at rule level only.

## Private key provider / TLS acceleration (`tasks/security/private-key-provider.md`)

- **Not a first-class EG API** — requires
  `extensionApis.enableEnvoyPatchPolicy: true` +
  `envoyproxy/envoy-contrib-dev` image.
- Two providers: QAT (Intel QuickAssist) and CryptoMB (AVX-512 CPUs).
- `EnvoyPatchPolicy` (`type: JSONPatch`) targets
  `type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.Secret`
  named `<ns>/<secret-name>`.

## Threat model (`tasks/security/threat-model.md`)

High-priority findings for operators: self-signed certs, private keys in
K8s Secrets, wide ClusterRoles, **privilege escalation via EnvoyProxy
deployment patch (EGTM-026)**, cross-namespace co-tenant misconfig via
ReferenceGrants, excessive privileges via extension policies.
Recommended posture: per-tenant controller in tenant-owned namespace
rather than shared controller. v1.9.2: disable the `EnvoyProxyPatch`
runtime flag on multi-tenant clusters.

## Experimental / disabled-by-default flags (roll-up)

- `extensionApis.enableSDSSecretRef: true` — SDS cert refs, default off.
- `extensionApis.enableBackend: true` — `Backend` CR, default off.
- `extensionApis.enableEnvoyPatchPolicy: true` — escape hatch; see
  threat model.
- Basic auth: SHA-only htpasswd. API key: no `Bearer` prefix stripping.
  OIDC: HTTPS redirect required. TCPRoute SecurityPolicy: CIDR
  authorization only. Credential injection on GRPCRoute: rule-level
  only.
