---
name: envoy-gateway
description: "Envoy Gateway v1.9.x reference router for Kubernetes. Load for any Envoy Gateway task: installing or upgrading (helm/egctl/yaml/Argo CD/Flux), Gateway API routing (GatewayClass/Gateway/HTTPRoute/GRPCRoute/TLSRoute/TCPRoute/UDPRoute), the gateway.envoyproxy.io CRDs (EnvoyProxy, Backend, ClientTrafficPolicy, BackendTrafficPolicy, SecurityPolicy, EnvoyExtensionPolicy, EnvoyPatchPolicy, HTTPRouteFilter), TLS/cert-manager/OIDC/JWT/API-key, rate limiting, load balancing, observability, egctl, or debugging gateways stuck pending / routes not programming / TLS failures. Includes dedicated Cilium guidance (kube-proxy replacement, nftables, BGP control plane v2 + LB IPAM) — use whenever Envoy Gateway runs on Cilium, even if the user only says 'gateway' or 'ingress'. Use this skill even when the user does not name a specific subfeature."
---

# envoy-gateway

[Envoy Gateway](https://gateway.envoyproxy.io) is the Kubernetes Gateway
API controller that manages Envoy Proxy fleets. Assumed platform: Cilium
CNI with kube-proxy replacement, nftables, BGP control plane v2 + LB
IPAM (see [references/cilium.md](references/cilium.md)).

## Version rule

- **Envoy Gateway v1.9.2 is the verified baseline** for this skill.
- Shipped with: Envoy Proxy distroless-v1.39.x, Gateway API (sig-network)
  **v1.6.1** (experimental channel by default), Kubernetes v1.33–v1.36.
  1.9.x is supported until **2027-02-14**.
- Use versioned docs for the cluster's actual release:
  `https://gateway.envoyproxy.io/docs/...` tracks latest; release notes
  at `https://gateway.envoyproxy.io/news/releases/notes/v<X.Y.Z>/`.
- Post-1.9 / main-branch changes are called out explicitly in
  [references/releases.md](references/releases.md). Do not treat them as
  v1.9 facts.

## Choose the reference

| Task | Read this reference |
|---|---|
| Install, upgrade, helm values, certs, deployment modes, EnvoyProxy infra knobs, graceful shutdown, air-gap | [references/install-operations.md](references/install-operations.md) |
| CRD inventory, Gateway API v1.6 support matrix, policy attachment/precedence/merge rules, xDS pipeline | [references/crds-policies.md](references/crds-policies.md) |
| Routing & traffic recipes: HTTP/gRPC/TCP/UDP/TLS routes, splitting, rewrites, timeouts, retries, circuit breaking, LB, rate limit, Backend | [references/traffic.md](references/traffic.md) |
| TLS termination/passthrough, cert-manager, mTLS, BackendTLSPolicy, JWT/OIDC/ext-auth/API-key/CORS/CSRF/IP rules | [references/security.md](references/security.md) |
| Access logs/metrics/tracing, egctl, admin consoles, EnvoyPatchPolicy, wasm/lua/ext-proc, debugging workflow | [references/observability-troubleshooting.md](references/observability-troubleshooting.md) |
| Running on Cilium: GatewayClass coexistence, LB IPAM + BGP recipe, KPR/nftables facts, CNP interactions, checklist | [references/cilium.md](references/cilium.md) |
| Version support policy, compatibility matrix, v1.9.0/1/2 breaking changes, post-1.9 previews | [references/releases.md](references/releases.md) |

## Cross-branch global gotchas

- **Gateway API v1.6 CRDs before EG v1.9.** TCP/UDP routes are silently
  skipped otherwise; `v1alpha2` TCPRoute/UDPRoute manifests are dead on
  the standard channel. On Cilium: install Gateway API v1.6.3 CRDs and
  EG with `--set crds.gatewayAPI.enabled=false`.
- **Never install v1.9.0.** The 1.9.0→1.9.1 in-place upgrade breaks TLS
  on running proxies (envoyproxy/envoy#47309). Go straight to ≥1.9.1.
- **One controller = one GatewayClass** (default controllerName
  `gateway.envoyproxy.io/gatewayclass-controller`). One Gateway = one
  Envoy fleet + one Service (type `LoadBalancer` by default,
  externalTrafficPolicy `Local` by default).
- **Policies are same-namespace only**; most specific attachment wins;
  overridden policies show `Overridden=True`. `targetRef` (singular) is
  deprecated — use `targetRefs`/`targetSelectors`.
- **Off by default**: `Backend` CRD, Lua, EnvoyPatchPolicy, SDS cert
  refs — each needs an `extensionApis.enable*` flag in the EnvoyGateway
  config. EnvoyPatchPolicy / extension managers carry "complete
  security compromise" warnings.
- **Rate limits and circuit breakers are per-route** even when the
  policy targets a Gateway; local rate limit is also per-Envoy-replica.
- **Default request timeout is 15s** — streaming gRPC/WebSocket needs
  `requestTimeout: 0s` via BackendTrafficPolicy.
- **Rejected config → HTTP 500 with `direct_response`**, not a status
  error on the client side; check route/policy status conditions and
  `egctl x status all -A`.
- On Cilium: leave Cilium's own Gateway API controller disabled
  (`gatewayAPI.enabled=false`, its default), keep `loadBalancerClass`
  unset on the envoy Service, and let BGP advertise per-node VIPs under
  eTP `Local`. Full recipe in the Cilium reference.

## Core doc URLs

| Topic | URL |
|---|---|
| Docs home | https://gateway.envoyproxy.io/docs |
| Install | https://gateway.envoyproxy.io/docs/install |
| API reference (CRD fields) | https://gateway.envoyproxy.io/docs/api/extension_types |
| Tasks (recipes) | https://gateway.envoyproxy.io/docs/tasks |
| Release notes | https://gateway.envoyproxy.io/news/releases |
| Compatibility matrix | https://gateway.envoyproxy.io/news/releases/matrix |
| Source | https://github.com/envoyproxy/gateway |
| Gateway API spec | https://gateway-api.sigs.k8s.io |
