# Envoy Gateway on Cilium — kube-proxy replacement + nftables + BGP CP v2 + LB IPAM

Target environment: Cilium with `kubeProxyReplacement=true`, nftables
mode (no iptables), Cilium BGP Control Plane v2
(`CiliumBGPClusterConfig`/`CiliumBGPAdvertisement`) with Cilium LB IPAM
(`CiliumLoadBalancerIPPool`) for LoadBalancer IPs. Companion skill:
`cilium` (house reference for pool/BGP selector mechanics).

## Coexistence & GatewayClass ownership

- A `Gateway` references a `GatewayClass`; each
  `GatewayClass.spec.controllerName` binds it to exactly one controller.
  Cilium's class uses `io.cilium/gateway-controller`; EG's uses
  **`gateway.envoyproxy.io/gatewayclass-controller`**. Two controllers
  side by side is the normal multi-implementation Gateway API topology —
  each only reconciles Gateways whose class it owns. No fighting.
- Cilium's Gateway API controller is **off by default**
  (`gatewayAPI.enabled=false` in Helm), so on a default Cilium install
  nothing competes with EG. If it was enabled: set
  `gatewayAPI.enabled=false` and roll `deployment/cilium-operator` +
  `ds/cilium` (restart required). Delete the auto-created `cilium`
  GatewayClass (`gatewayAPI.gatewayClass.create=auto` recreates it
  while the feature is on).
- If you keep both: separate GatewayClasses (default behavior); don't
  point the same Gateway at both.
- **CRD version compatibility is the real constraint.** EG v1.9.2
  requires Gateway API CRDs **v1.6** (TCP/UDP routes silently skipped
  otherwise). Cilium 1.20 supports Gateway API v1.6.3, minimum v1.6.1 →
  install Gateway API **v1.6.3 CRDs**; both are satisfied. Existing
  `v1alpha2` TLSRoute users need the *experimental* channel CRDs (Cilium
  side).
- When CRDs are managed outside EG's chart (by Cilium or GitOps),
  install EG with `--set crds.gatewayAPI.enabled=false` /
  `--set crds.enabled=false` — EG documents this "provider-managed
  CRDs" mode and warns not to mix two copies of the CRDs.
- Failure pattern on class/controller mismatch: Gateway stuck "Waiting
  for controller" (cilium#39322 shows the symptom shape).

## LoadBalancer Service + Cilium LB IPAM/BGP recipe

EG's `EnvoyProxy` Kubernetes provider exposes the full service knob set:
`type` (default `LoadBalancer`), `loadBalancerClass`,
`allocateLoadBalancerNodePorts`, `loadBalancerSourceRanges`,
`loadBalancerIP`, `externalTrafficPolicy` (**EG default `Local`** — not
Cluster!), `annotations`, `labels`, and a strategic-merge `patch`.
EG-managed Services carry labels
`gateway.envoyproxy.io/owning-gateway-name` / `...-namespace`.

```yaml
# 1. Pool — selector optional; without one the pool serves any LB service
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata: {name: gateway-pool}
spec:
  blocks: [{cidr: "192.168.10.0/28"}]
  serviceSelector:
    matchLabels:
      gateway.envoyproxy.io/owning-gateway-namespace: gateways
---
# 2. BGP advertisement — selector must match the EG-managed Service labels;
#    and CiliumBGPClusterConfig families[].advertisements must match THIS CR's labels
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata: {name: gateway-vips, labels: {advertise: gateway}}
spec:
  advertisements:
    - advertisementType: Service
      service: {addresses: [LoadBalancerIP]}
      selector:
        matchLabels:
          gateway.envoyproxy.io/owning-gateway-namespace: gateways
---
# 3. EnvoyProxy — pin annotations/labels through to the managed Service
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata: {name: cilium-bgp, namespace: gateways}
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        type: LoadBalancer
        # loadBalancerClass: leave UNSET (Cilium LB IPAM serves classless
        # services; BGP announces only unset or io.cilium/bgp-control-plane)
        externalTrafficPolicy: Local   # EG default; pairs well with BGP
        annotations:
          lbipam.cilium.io/ips: "192.168.10.5"   # optional static VIP
---
# 4. Gateway — attach EnvoyProxy via infrastructure.parametersRef;
#    infrastructure.annotations also propagate to the Service
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: eg, namespace: gateways}
spec:
  gatewayClassName: envoy-gateway
  infrastructure:
    annotations:
      lbipam.cilium.io/ips: "192.168.10.5"      # alternative injection point
    parametersRef: {group: gateway.envoyproxy.io, kind: EnvoyProxy, name: cilium-bgp}
  listeners: [...]
```

- `Gateway.spec.addresses` (type `IPAddress`) maps to the Service's
  externalIPs and requires type LB/NodePort — if set it becomes the
  *only* Gateway status address.
- **externalTrafficPolicy discrepancy**: EG defaults to `Local` while
  Cilium's own gateway defaults to `Cluster`. With BGP (unlike L2
  announcements) `Local` is correct and beneficial: Cilium advertises
  the VIP only from nodes with local envoy endpoints and withdraws when
  none exist. Known wrinkle: rolling restarts under `Local` can briefly
  blackhole (cilium#19810) — use enough replicas / graceful shutdown.

## kube-proxy-replacement & nftables facts that matter

- EG's datapath does not consume ClusterIP at all: it builds Envoy
  clusters (EDS) from **EndpointSlices**. Whether the node's service LB
  is kube-proxy-iptables, kube-proxy-nftables, or Cilium eBPF is
  invisible to EG upstream routing. **nftables vs iptables does not
  matter for EG.**
- What *does* run through Cilium's KPR datapath: the north/south hop
  from the BGP-advertised VIP to an envoy pod (LB service DNAT in
  eBPF). That path is pure BPF under `kubeProxyReplacement=true`.
- iptables caveats belong to *Cilium's own* L7 features, not EG:
  Cilium's gateway/L7 proxy needs TPROXY, which by default
  (`bpf.tproxy=false`) uses iptables. If Cilium gateway-api is disabled
  and no L7 CNPs are used, a no-iptables host is fine for EG. (Cilium
  masquerade: use `bpf.masquerade=true` on iptables-less hosts.)
  *Unverified: exact Cilium 1.20 behavior on a host with zero iptables
  tooling present.*
- Health checking without kube-proxy: no external LB health checker
  exists in the BGP model. "Health" = endpoint existence: eTP `Local`
  withdraws per-node VIPs with no local envoy pod. In-cluster health is
  EG's job: `BackendTrafficPolicy` active health checks and passive
  outlier detection probe **pod IPs directly**. No
  NodePort/healthCheckNodePort considerations apply with BGP. If you
  set `envoyService.type: ClusterIP` or `NodePort`, you lose BGP VIP
  advertisement — keep `LoadBalancer`.
- Historical EG+Cilium LB issues, both closed and L2-specific (don't
  apply to BGP): envoyproxy/gateway#3093, cilium#39556.

## L7 policy / CEC interactions

- Cilium's Envoy (embedded or `cilium-envoy` DaemonSet) is only engaged
  by Cilium's own features: L7 network policy, Cilium Ingress/Gateway
  API, CEC/CCEC. EG's envoy proxies are ordinary pods — Cilium does not
  inject redirects into them, so there are **no port/admin-interface
  conflicts** (Cilium envoy admin is a UDS).
- L3/L4 CiliumNetworkPolicy **does** apply to EG pods normally.
  External traffic DNAT'd from the VIP to envoy pods arrives with the
  original client source IP (under eTP `Local` there's no cross-node
  SNAT), so the source identity is `world`. If any policy selects the
  envoy pods, you must allow `world` ingress. (Cf. cilium#34786.)
  *Standard Cilium reasoning; no EG-specific doc statement found.*
- Do **not** apply L7 (HTTP/gRPC rules) CNPs to EG proxy pods — that
  would redirect their traffic through cilium-envoy and double-proxy.
  *Recommendation by reasoning, not documented.*
- CEC/CCEC: nothing EG does generates CiliumEnvoyConfigs. Hand-written
  CECs are global to Cilium's envoy and won't touch EG pods; CECs have
  no apiserver validation — silent xDS rejection possible.
- Source-IP visibility: with eTP `Local` + BGP, envoy sees the real
  client IP directly (no XFF games needed); EG additionally has
  `directSourceIP` client-IP detection for L4-transparent topologies.

## EG-on-Cilium troubleshooting checklist

1. **GatewayClass**: `kubectl get gatewayclass` — EG's class must show
   `ACCEPTED=True`; wrong controllerName ⇒ "Waiting for controller"
   forever.
2. **Gateway Programmed / address**: `kubectl describe gateway -n
   <ns>`; check the managed Service: `kubectl get svc -A -l
   gateway.envoyproxy.io/owning-gateway-name=<gw>` — is an EXTERNAL-IP
   assigned? If `<pending>`: `kubectl get ippools`, pool
   `cilium.io/PoolConflict`, and Service condition
   `io.cilium/lb-ipam-request-satisfied=False` (`no_pool` ⇒ pool's
   `serviceSelector` doesn't match the service labels).
3. **IP assigned but unreachable**: the classic BGP silence chain —
   `CiliumBGPClusterConfig` family has an `advertisements` selector →
   matches labels on a `CiliumBGPAdvertisement` → its `selector`
   matches the EG Service labels → `service.addresses` includes
   `LoadBalancerIP`. Verify: `cilium bgp peers`, `cilium bgp routes
   advertised ipv4 unicast`.
4. **Intermittent connectivity**: eTP `Local` + no local envoy pod on
   the node you landed on ⇒ VIP withdrawn there (expected), or
   cilium#19810 restart window. Check pod placement vs advertised
   next-hops.
5. **502 / no healthy upstream**: envoy EDS empty ⇒ check
   EndpointSlices of the backend Service, EG controller logs (`kubectl
   logs -n envoy-gateway-system deploy/envoy-gateway`), and policy
   status. Admin console: `kubectl port-forward -n envoy-gateway-system
   deploy/envoy-gateway 19000`.
6. **Policy drops**: `hubble observe --identity 2 -f` / `cilium-dbg
   monitor --type drop` for world→envoy-pod denies.
7. **After toggling Cilium `gatewayAPI.enabled`**: restart `ds/cilium`
   + `deploy/cilium-operator`, and re-check for a stale `cilium`
   GatewayClass.
8. **TCP/UDP routes silently absent**: Gateway API CRDs older than v1.6
   with EG 1.9.2.

## Source index

| Claim | Source |
|---|---|
| EG controller name, class ownership, eTP patch, infra annotations → svc | surajremanan.com EG-on-Cilium guide (field-verified) |
| envoyService fields incl. eTP default Local, loadBalancerClass, patch | `api/extension_types.md` @ v1.9.2 |
| Gateway API v1.6 CRD requirement, provider-managed CRD install mode | `install/install-helm.md` @ v1.9.2 |
| Pool/BGP/selector mechanics, eTP Local withdrawal, loadBalancerClass rule, lbipam annotations | house `cilium` skill `references/bgp-loadbalancer.md` |
| Cilium gateway-api prerequisites, TPROXY/iptables, ingress identity | house `cilium` skill `references/gateway-api.md` |
| eTP Local restart blackhole | cilium#19810 |
| L2 + EG issues (closed) | envoyproxy/gateway#3093, cilium#39556 |
| EG consumes EndpointSlices | envoyproxy/gateway#10191 |

**Unverified flags:** (1) Cilium 1.20 behavior on a host with no
iptables binaries at all; (2) `world` identity for external traffic to
EG pods — standard Cilium reasoning, no EG-specific doc; (3) "don't
apply L7 CNP to EG pods" — recommendation by reasoning; (4) no open
GitHub issue describes a *fundamental* EG↔Cilium-KPR conflict — the
issues that exist are L2-announcement-specific and closed.
