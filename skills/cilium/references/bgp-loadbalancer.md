# Cilium 1.20 BGP, LB IPAM, and L2 announcements

## BGP Control Plane (v2)

The v2 BGP control plane advertises Pod and Service routes to external
routers. It **does not program the datapath** — do not use it for
in-cluster reachability.

- Speaker: GoBGP embedded in each Cilium agent.
- Operator translates `CiliumBGPClusterConfig` into per-node
  `CiliumBGPNodeConfig` resources.
- Enable: `bgpControlPlane.enabled=true`, then restart `ds/cilium`.

### The four user-facing CRDs

| CRD | Purpose |
|---|---|
| `CiliumBGPClusterConfig` | BGP instances + peers, applied cluster-wide by `nodeSelector`. Max 16 BGP instances per config. |
| `CiliumBGPPeerConfig` | Shared peer settings: timers, auth, multihop, graceful restart, transport, AFI/SAFI. |
| `CiliumBGPAdvertisement` | What gets advertised and with what attributes (communities, local preference). |
| `CiliumBGPNodeConfigOverride` | Per-node overrides. `metadata.name` must equal the node name; instance/peer names must match the `CiliumBGPClusterConfig`. |

`CiliumBGPNodeConfig` is operator-generated and read-only for users.

### Key behaviors

- **No listener by default** — instances only dial out unless `localPort`
  is set. Port 179 requires `CAP_NET_BIND_SERVICE` via
  `securityContext.capabilities.ciliumAgent`.
- **Auto-discovery** — `peers[].autoDiscovery.mode = "DefaultGateway"`
  peers with the node's default gateway per address family. The ToR must
  run `bgp listen range` for dynamic neighbors with the same local ASN.
  Link-local default gateways are not supported; multi-homing picks the
  lower-metric default route only.
- **MD5 auth** — `CiliumBGPPeerConfig.spec.authSecretRef` points at a
  Secret with key `password` in the BGP secrets namespace (default
  `kube-system`). TCP MD5 fails silently behind NAT (`dial: i/o
  timeout`). A missing Secret logs an error and the session proceeds
  with an empty password.
- **Timers** — defaults: `connectRetryTimeSeconds=120`,
  `holdTimeSeconds=90`, `keepAliveTimeSeconds=30`. For fast
  datacenter/ToR detection use hold 9 / keepalive 3 / connect-retry 5.
  Minimum documented: hold 3 / keepalive 1. **No BFD support in 1.20.**
- **Graceful restart** — `gracefulRestart.enabled=true` keeps the peer
  forwarding during agent restarts. `restartTimeSeconds` (default 120)
  must exceed agent boot/image-pull time.
- **eBGP multihop** — set `ebgpMultihop` for route servers in other
  subnets.
- **Address families** — `afi`/`safi` pairs (`ipv4|ipv6` × `unicast`)
  plus an `advertisements` label selector. **Without a matching
  selector no prefix is advertised** — the most common "session up, no
  routes" cause.

### Advertisements

`CiliumBGPAdvertisement` resources are matched by the `advertisements`
label selector in peer-config families.

| `advertisementType` | Advertises | Notes |
|---|---|---|
| `PodCIDR` | Node's allocated pod CIDR | Kubernetes/ClusterPool IPAM only |
| `CiliumPodIPPool` | CIDRs from selected pools | MultiPool IPAM; selector on pool labels |
| `Service` | Service VIPs | `service.addresses`: `LoadBalancerIP`, `ClusterIP`, `ExternalIP`; label selector picks services |
| `Interface` | Local interface IPs (/32, /128) | e.g. loopback in multi-homing; interface must be up |

Attributes per entry: `communities` (standard `65000:99`, well-known
`no-export`, large `a:b:c`) and `localPreference` (iBGP only, ignored
for eBGP). Overlapping selectors are supported since 1.18: communities
union, local preference takes the max.

Service advertisement specifics:

- VIPs advertise as exact /32 (or /128); aggregate with
  `service.aggregationLengthIPv4/IPv6`.
- Aggregation risk: aggregated prefixes covering unassigned addresses
  can blackhole or route-loop (cilium#37623); overlapping aggregations
  with different attributes are undefined (cilium#40585).
- ECMP upstream load-balances across nodes advertising the same VIP —
  check the router's ECMP path limit.
- `externalTrafficPolicy: Local` (and `internalTrafficPolicy: Local` for
  ClusterIPs) withdraw the VIP when no local endpoints exist; `Cluster`
  advertises unconditionally. Aggregation lengths are ignored under
  `Local`.
- `loadBalancerClass` must be unset or `io.cilium/bgp-control-plane` for
  ingress IPs to be announced.

### Router ID

`bgpControlPlane.routerIDAllocation.mode`:

- `default` — node's IPv4 address; on IPv6 single-stack, lower 32 bits
  of `cilium_host` MAC.
- `ip-pool` — allocate from
  `bgpControlPlane.routerIDAllocation.ipPool`.

Manual override per node via `CiliumBGPNodeConfigOverride`
`bgpInstances[].routerID`.

### Status conditions

| Resource | Condition | Meaning |
|---|---|---|
| `CiliumBGPClusterConfig` | `cilium.io/NoMatchingNode` | `nodeSelector` matches nothing |
| `CiliumBGPClusterConfig` | `cilium.io/ConflictingClusterConfig` | Another ClusterConfig selects the same node |
| `CiliumBGPClusterConfig` | `cilium.io/MissingPeerConfigs` | A `peerConfigRef` name doesn't resolve |
| `CiliumBGPPeerConfig` | `cilium.io/MissingAuthSecret` | Referenced Secret missing; session proceeds with empty password |

### Diagnostics in 1.20

Prefer `cilium-dbg shell -- bgp/*` in 1.20; the older `cilium-dbg bgp`
and local REST API paths are deprecated.

```bash
# cluster-wide peering state (Cilium CLI)
cilium bgp peers
cilium bgp routes available ipv4 unicast
cilium bgp routes advertised ipv4 unicast

# per-agent, preferred in 1.20
kubectl -n kube-system exec <cilium-pod> -- cilium-dbg shell -- bgp/peers [-f detailed]
kubectl -n kube-system exec <cilium-pod> -- cilium-dbg shell -- bgp/routes [-a] in|out <afi> <safi>
kubectl -n kube-system exec <cilium-pod> -- cilium-dbg shell -- bgp/route-policies

# logs
kubectl -n kube-system logs <cilium-agent> | grep subsys=bgp-control-plane
kubectl -n kube-system logs <cilium-operator> | grep subsys=bgp-cp-operator

# generated per-node config
kubectl get ciliumbgpnodeconfigs
kubectl describe ciliumbgpnodeconfigs <node>
```

### Operational notes

- Node drain/shutdown: remove/flip the ClusterConfig `nodeSelector`
  label on the node, then wait for peer route withdrawal before
  powering off. Withdrawal is immediate without graceful restart,
  bounded by the stale timer with RFC 8538 GR, or by hold-time
  otherwise.
- If the operator is down, new `CiliumBGPNodeConfig` provisioning and
  LB-IPAM allocation stop.
- Pre-pull the agent image before upgrades; a slow pull can exceed
  `restartTimeSeconds` and trigger route withdrawal.

## LB IPAM

LB IPAM assigns IPs to `type: LoadBalancer` Services. It is always
enabled but dormant until the first `CiliumLoadBalancerIPPool` exists.
It pairs with BGP control plane or L2 announcements for actual
advertising.

```yaml
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: blue-pool
spec:
  blocks:
    - cidr: "10.0.10.0/24"
    - start: "20.0.20.100"
      stop: "20.0.20.200"
  serviceSelector:
    matchExpressions:
      - {key: color, operator: In, values: [blue, cyan]}
```

- `allowFirstLastIPs: No` reserves network/broadcast addresses for CIDR
  blocks; ignored for /31, /32 and v6 equivalents.
- Overlapping CIDRs: the last-added pool is marked `Conflicting`
  (`cilium.io/PoolConflict`) and stops allocating.
- Updating a pool can reassign IPs and change Service VIPs
  (cilium#40358) — plan changes.
- `disabled: true` drains a pool (no new allocations, existing kept).
- Service annotations:
  - `lbipam.cilium.io/ips` — request specific IPs (comma-separated).
  - `lbipam.cilium.io/sharing-key` — share VIPs across Services.
  - `lbipam.cilium.io/sharing-cross-namespace` — allow cross-namespace
    sharing; must be present on **both** Services.
- Allocation failures surface as Service status condition
  `io.cilium/lb-ipam-request-satisfied` = `False` (e.g. reason
  `no_pool`).
- By default LB IPAM also serves Services with no `loadBalancerClass`;
  set Helm `defaultLBServiceIPAM=none` to require an explicit class.

### LoadBalancer classes handled by Cilium

| `loadBalancerClass` | Feature |
|---|---|
| (unset) | LB IPAM allocates |
| `io.cilium/bgp-control-plane` | BGP Control Plane |
| `io.cilium/l2-announcer` | L2 Announcements |

If the class is not handled by Cilium, LB IPAM ignores the Service and
does **not** set a status condition.

## L2 announcements (beta)

ARP/NDP-based alternative to BGP for flat L2 networks. One node per VIP
answers ARP/NDP with its MAC; north/south load-balancing happens once
traffic enters the cluster.

- Enable: `l2announcements.enabled=true`, `kubeProxyReplacement=true`,
  plus size `k8sClientRateLimit.qps/burst`.
- CRD: `CiliumL2AnnouncementPolicy` (`cilium.io/v2alpha1`).
- Policy fields: `serviceSelector`, `nodeSelector`, `interfaces`
  (regex), `externalIPs`, `loadBalancerIPs`.
- Service `loadBalancerClass` must be unset or `io.cilium/l2-announcer`.
- Incompatible with `externalTrafficPolicy: Local` — may announce IPs on
  nodes without pods, causing drops.
- Leader election uses Kubernetes `Lease` objects in the Cilium
  namespace. Missing `coordination.k8s.io` leases RBAC is a common
  manual-install failure.
- Lease tuning defaults: `leaseDuration=15s`, `leaseRenewDeadline=5s`,
  `leaseRetryPeriod=2s`.
- If using `externalIPs`, enable `externalIPs.enable=true`.
- L2 Pod Announcements is a separate feature
  (`l2podAnnouncements.enabled=true`, `l2podAnnouncements.interfacePattern`);
  only ARP, no IPv6 yet.

## Gotchas

- BGP default is silence: no listener and no advertisements until
  explicitly configured.
- "Session up but nothing advertised" is almost always the
  `families[].advertisements` selector missing a matching
  `CiliumBGPAdvertisement` label.
- No BFD in 1.20 — tune timers for fast failure detection.
- BGP is not a datapath reachability solution inside the cluster.
- Port 179 listener needs `CAP_NET_BIND_SERVICE` on the agent
  container.
- ClusterConfig node selection must not overlap; one config per node.
- MD5 auth breaks behind NAT and degrades to empty password when the
  Secret is missing.
- ECMP + VIPs: watch router ECMP path limits; resilient hashing/Maglev
  help connection survival under `Cluster` policy.

## References

- [BGP control plane](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane/)
- [BGP configuration](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-configuration/)
- [BGP operation](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/)
- [BGP troubleshooting](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/)
- [LB IPAM](https://docs.cilium.io/en/v1.20/network/lb-ipam/)
- [L2 announcements](https://docs.cilium.io/en/v1.20/network/l2-announcements/)
