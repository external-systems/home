---
name: cilium
description: "Cilium 1.20+ reference router. Load for any Cilium task: custom resources/API versions, BGP v2 control plane, LoadBalancer IPAM, L2 announcements, Gateway API, Cluster Mesh, network policy (CNP/CCNP/CIDRGroup/FQDN/L7), CiliumEnvoyConfig, observability, or troubleshooting. Use this skill even when the user does not name a specific subfeature."
---

# cilium

[Cilium](https://docs.cilium.io) is the eBPF-based networking,
observability, and security layer for Kubernetes.

## Version rule

- **Cilium v1.20.0 is the verified baseline** for this skill.
- Use versioned docs for the cluster's actual release:
  `https://docs.cilium.io/en/v1.20/...` for 1.20 claims,
  `https://docs.cilium.io/en/stable/...` for rolling latest.
- Post-1.20 / main-branch changes are called out explicitly in the
  reference files. Do not treat them as 1.20 facts.

## Choose the reference

| Task | Read this reference |
|---|---|
| CRD inventory, API versions, scope, lifecycle, feature index | [references/custom-resources.md](references/custom-resources.md) |
| BGP v2, LB IPAM, L2 announcements, LoadBalancer classes | [references/bgp-loadbalancer.md](references/bgp-loadbalancer.md) |
| Gateway API, CiliumGatewayClassConfig, TLSRoute 1.20 change | [references/gateway-api.md](references/gateway-api.md) |
| Cluster Mesh setup, global services, MCS-API, cross-cluster policy | [references/clustermesh.md](references/clustermesh.md) |
| Network policy: K8s NP, CNP/CCNP, CIDRGroup, FQDN, L7, deny | [references/network-policy.md](references/network-policy.md) |
| CiliumEnvoyConfig / CiliumClusterwideEnvoyConfig | [references/envoy-config.md](references/envoy-config.md) |
| Symptom-to-doc map, commands, conditions, logs, metrics, safety | [references/troubleshooting.md](references/troubleshooting.md) |

Source-evidence research files (keep unchanged):
[references/research/crds-1.20.md](references/research/crds-1.20.md),
[references/research/features-1.20.md](references/research/features-1.20.md),
[references/research/troubleshooting-1.20.md](references/research/troubleshooting-1.20.md).

## Cross-branch global gotchas

- **BGP ≠ datapath**. BGP advertises routes to external routers; it
  does not establish in-cluster reachability.
- **Default BGP silence**. Without `localPort` and a matching
  `families[].advertisements` selector, sessions initiate but advertise
  nothing.
- **No BFD in 1.20**. Use hold/keepalive timers for fast failure
  detection.
- **One `CiliumBGPClusterConfig` per node**. Overlapping node selectors
  are rejected.
- **LB IPAM pairs with an advertiser**. LB IPAM allocates IPs; BGP or
  L2 announcements makes them reachable.
- **L2 announcements are incompatible with `externalTrafficPolicy: Local`**.
- **Gateway API needs `kubeProxyReplacement=true` and `l7Proxy=true`**.
- **Cluster Mesh is a single trust domain**. All connected clusters
  trust each other.
- **Policy is identity-based**. Default-deny kicks in once a policy
  selects an endpoint in the relevant direction.
- **CEC / CCEC have no API-server validation**. `kubectl apply` can
  succeed while Envoy rejects the config; check agent logs.

## Core doc URLs

| Topic | v1.20 pinned URL |
|---|---|
| Docs home | https://docs.cilium.io/en/v1.20 |
| BGP control plane | https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane |
| LB IPAM | https://docs.cilium.io/en/v1.20/network/lb-ipam |
| L2 announcements | https://docs.cilium.io/en/v1.20/network/l2-announcements |
| Gateway API | https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/gateway-api |
| Cluster Mesh setup | https://docs.cilium.io/en/v1.20/network/clustermesh/setup |
| Network policy | https://docs.cilium.io/en/v1.20/security/policy |
| L7 traffic management / CEC | https://docs.cilium.io/en/v1.20/network/servicemesh/l7-traffic-management |
| Troubleshooting | https://docs.cilium.io/en/v1.20/operations/troubleshooting |
| Metrics | https://docs.cilium.io/en/v1.20/observability/metrics |
| Upgrade guide | https://docs.cilium.io/en/v1.20/operations/upgrade |
| Source | https://github.com/cilium/cilium |
