# Cilium 1.20 troubleshooting

A symptom-to-first-doc map plus verified commands, status conditions,
logs, metrics, and safety notes. Use the pinned v1.20 docs for 1.20
clusters; use the rolling stable docs for newer releases.

## Symptom-to-first-doc map

| Symptom / observation | First doc to open |
|---|---|
| Cilium pods unhealthy, `cilium-dbg status` failures, general cluster health | [operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| Pod-to-pod works on one node but fails across nodes; packet drops in `cilium-dbg monitor` | [operations/troubleshooting — Connectivity Problems](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#connectivity-problems) |
| Traffic unexpectedly blocked by policy; FQDN not working | [security/policy/troubleshooting](https://docs.cilium.io/en/v1.20/security/policy/troubleshooting/) |
| Pods not managed by Cilium | [operations/troubleshooting — Ensure pod is managed](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#ensure-managed-pod) |
| BGP config applied but no `CiliumBGPNodeConfig`; session not established; routes missing | [BGP troubleshooting](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/) |
| BGP node drain, graceful restart, route-withdrawal timing | [BGP operation](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) |
| LoadBalancer Service `<pending>`; conflicting pools; VIPs changed | [LB IPAM](https://docs.cilium.io/en/v1.20/network/lb-ipam/) |
| ARP/NDP for Service VIP not answered; L2 lease flapping | [L2 announcements](https://docs.cilium.io/en/v1.20/network/l2-announcements/) |
| Gateway not `Programmed`; HTTPRoute not attached; no address | [Gateway API troubleshooting](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/) |
| Ingress 503 / no healthy upstream; CiliumEnvoyConfig conflict | [operations/troubleshooting — Service Mesh](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#service-mesh-troubleshooting) |
| Cluster Mesh not ready; TLS errors; remote state missing | [Cluster Mesh setup — Troubleshooting](https://docs.cilium.io/en/v1.20/network/clustermesh/setup/#troubleshooting) |
| Hubble Relay not ready; TLS/cert errors | [Hubble setup](https://docs.cilium.io/en/v1.20/observability/hubble/setup/) / [Hubble TLS](https://docs.cilium.io/en/v1.20/observability/hubble/configuration/tls/) |
| Upgrade failure; pre-flight failure | [Upgrade guide](https://docs.cilium.io/en/v1.20/operations/upgrade/) |
| Need metric names for alerting | [Metrics reference](https://docs.cilium.io/en/v1.20/observability/metrics/) |

## Verified commands by area

### General health

```bash
kubectl -n kube-system get pods -l k8s-app=cilium
kubectl -n kube-system exec <cilium-pod> -- cilium-dbg status [--verbose]
cilium status
kubectl -n kube-system logs --timestamps [-p] <cilium-pod>
kubectl -n kube-system exec ds/cilium -- cilium-dbg config --all | grep <OPTION>
```

### Connectivity / datapath

```bash
kubectl -n kube-system exec -ti <cilium-pod> -- cilium-health status --verbose
kubectl -n kube-system exec -ti <cilium-pod> -- cilium-dbg monitor --type drop
kubectl -n kube-system exec ds/cilium -- cilium-dbg bpf ipcache list
cilium connectivity test [--multi-cluster <ctx2>]
```

### Policy / identity / endpoint

```bash
kubectl -n kube-system exec -ti <cilium-pod> -- cilium-dbg endpoint list
kubectl -n kube-system exec -ti <cilium-pod> -- cilium-dbg endpoint get <id>
cilium-dbg fqdn cache list
cilium-dbg ip list | grep <IP>
cilium-dbg policy selectors
cilium-dbg identity list
```

### BGP v2 (preferred 1.20 path)

```bash
kubectl get ciliumbgpnodeconfigs
kubectl describe ciliumbgpnodeconfigs <node>
cilium bgp peers
cilium bgp routes available ipv4 unicast
cilium bgp routes advertised ipv4 unicast
kubectl -n kube-system exec <cilium-pod> -- cilium-dbg shell -- bgp/peers [-f detailed]
kubectl -n kube-system exec <cilium-pod> -- cilium-dbg shell -- bgp/routes [-a] in|out <afi> <safi>
kubectl -n kube-system exec <cilium-pod> -- cilium-dbg shell -- bgp/route-policies
kubectl -n kube-system logs <cilium-agent> | grep subsys=bgp-control-plane
kubectl -n kube-system logs <cilium-operator> | grep subsys=bgp-cp-operator
```

### LB IPAM / L2 announcements

```bash
kubectl get ippools
kubectl get ippools/<pool> -o jsonpath='{.status.conditions[?(@.type=="cilium.io/PoolConflict")].message}'
kubectl get svc/<svc> -o jsonpath='{.status.conditions}'
kubectl -n kube-system exec ds/cilium -- cilium-dbg config --all | grep -E 'EnableL2Announcements|KubeProxyReplacement|EnableExternalIPs'
kubectl get CiliumL2AnnouncementPolicy
kubectl -n kube-system get lease | grep cilium-l2announce
kubectl -n kube-system exec <holder-agent> -- cilium-dbg shell -- db/show l2-announce
kubectl -n kube-system exec ds/cilium -- cilium-dbg shell -- db/show devices
bpftool map dump pinned /sys/fs/bpf/tc/globals/cilium_l2_responder_v4
```

### Gateway API / Ingress / CiliumEnvoyConfig

```bash
kubectl get gateway -A
kubectl describe gateway <name>
kubectl describe httproute <name>
kubectl logs -n kube-system deployments/cilium-operator | grep gateway
kubectl get ingress / cec / svc cilium-ingress[-<name>]
curl -v http://localhost:<NodePort>/
kubectl -n kube-system exec ds/cilium -- hubble observe --identity 2\|8 -f
kubectl -n kube-system logs ds/cilium --timestamps | egrep 'envoy|proxy'
```

### Cluster Mesh

```bash
cilium clustermesh status --wait
kubectl -n kube-system exec ds/cilium -- cilium-dbg troubleshoot clustermesh
kubectl -n kube-system exec deploy/clustermesh-apiserver -c kvstoremesh \
  -- clustermesh-apiserver kvstoremesh-dbg troubleshoot
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --all-clusters
kubectl -n kube-system exec ds/cilium -- cilium-dbg node list
kubectl -n kube-system exec ds/cilium -- cilium-dbg bpf ipcache list
kubectl -n kube-system exec ds/cilium -- cilium-dbg shell -- db/show backends
kubectl -n kube-system exec ds/cilium -c cilium-agent -- ls /var/lib/cilium/clustermesh
```

### Hubble

```bash
cilium status
kubectl -n kube-system get pods -l k8s-app=hubble-relay
kubectl -n kube-system logs <hubble-relay-pod>
kubectl logs -n kube-system -c cilium-agent -l k8s-app=cilium --tail=-1 | grep subsys=hubble
kubectl -n kube-system exec <cilium-pod> -- hubble status
hubble status -P
hubble observe -P
hubble list nodes -P
```

### Sysdump / bugtool

```bash
cilium sysdump
cilium sysdump --node-list <nodes> --logs-since-time <time> --logs-limit-bytes <bytes>
kubectl -n kube-system exec <cilium-pod> -- cilium-bugtool
```

## CRD status conditions

| Resource | Condition | Meaning |
|---|---|---|
| `CiliumBGPClusterConfig` | `cilium.io/NoMatchingNode` | `nodeSelector` matches nothing |
| `CiliumBGPClusterConfig` | `cilium.io/ConflictingClusterConfig` | Another ClusterConfig selects the same node |
| `CiliumBGPClusterConfig` | `cilium.io/MissingPeerConfigs` | Referenced peer config does not exist |
| `CiliumBGPPeerConfig` | `cilium.io/MissingAuthSecret` | Referenced Secret missing; session proceeds with empty password |
| `CiliumLoadBalancerIPPool` | `cilium.io/PoolConflict` | Overlapping CIDR with another pool |
| `CiliumLoadBalancerIPPool` | `cilium.io/IPsTotal` / `IPsAvailable` / `IPsUsed` | Pool capacity counters |
| `Service` (type LoadBalancer) | `io.cilium/lb-ipam-request-satisfied` | `True`/`False` (e.g. `no_pool`) |
| `CiliumL2AnnouncementPolicy` | `io.cilium/bad-service-selector` | Invalid selector expression |
| `Gateway` | `Accepted` / `Programmed` / `ResolvedRefs` | Scheduling, programming, secret resolution |
| `HTTPRoute` | `Accepted` / `ResolvedRefs` | Route accepted; backend refs valid |

## Key log locations

| Component | Filter | Use |
|---|---|---|
| Cilium agent | `subsys=bgp-control-plane` | BGP session errors |
| Cilium operator | `subsys=bgp-cp-operator` | BGP resource translation |
| Cilium operator | `subsys=gateway-api` | Gateway API CRDs / controller errors |
| Cilium agent | `subsys=hubble` | Hubble startup/metric errors |
| Cilium agent | `subsys=klog` + leases | L2-announcement lease/RBAC errors |
| clustermesh-apiserver | `subsys=kvstore` | etcd session and remote sync errors |
| Cilium agent | `msg="Connection to remote cluster established"` / `Unable to establish etcd connection` | Cluster Mesh connectivity |

## Key metrics

### Agent / datapath

- `cilium_drop_count_total` (`reason`, `direction`)
- `cilium_forward_count_total` / `cilium_forward_bytes_total`
- `cilium_bpf_map_pressure{map_name="cilium_policy_v3_*"}`
- `cilium_datapath_conntrack_gc_entries`
- `cilium_node_health_connectivity_status` /
  `cilium_node_health_connectivity_latency_seconds`

### Policy / identity

- `cilium_policy`
- `cilium_policy_change_total`
- `cilium_policy_implementation_delay`
- `cilium_policy_missing_proxy_redirects`
- `cilium_identity_label_sources{type="fqdn"}`
- `cilium_endpoint_component_status`

### BGP

- `cilium_bgp_control_plane_session_state`
- `cilium_bgp_control_plane_advertised_routes`
- `cilium_bgp_control_plane_received_routes`
- `cilium_bgp_control_plane_reconcile_errors_total`

### LB IPAM (`cilium_` namespace)

- `cilium_lbipam_conflicting_pools`
- `cilium_lbipam_ips_available` / `cilium_lbipam_ips_used`
- `cilium_lbipam_services_matching` / `cilium_lbipam_services_unsatisfied`

### Cluster Mesh

- `cilium_clustermesh_remote_clusters`
- `cilium_clustermesh_remote_cluster_failures`
- `cilium_clustermesh_remote_cluster_readiness_status`
- `cilium_operator_clustermesh_remote_cluster_services` / `_endpoints` /
  `_endpoint_slices`

### Hubble

- `hubble_lost_events_total`
- `hubble_flows_processed_total`
- `hubble_drop_total`

## Safety notes

| Operation | Risk | Mitigation |
|---|---|---|
| `cilium sysdump` | Large/bandwidth-heavy on big clusters | Use `--node-list`, `--logs-since-time`, `--logs-limit-bytes` |
| `cilium-bugtool` | May capture sensitive data | Review and strip before sharing |
| `kubectl drain` on BGP nodes | Evicts workloads; routes still advertised | Follow BGP shutdown dance first |
| `kubectl label node --overwrite enable-bgp=false` | Tears down all BGP sessions | Wait for peer withdrawal before shutdown |
| `kubectl rollout undo daemonset/cilium` | Rollback after new features consumed can leave incompatible state | Check upgrade notes first |
| `cilium connectivity test` | Deploys pods/policies into `cilium-test` | Run only in an isolated test namespace |
| Updating `CiliumLoadBalancerIPPool` | Can reassign IPs / change VIPs | Plan changes; check conflicts first |
| `debug-verbose=flow` + `debug=true` | High log volume and CPU | Enable only targeted, then revert |

## Open questions

- `cilium` CLI (not `cilium-dbg`) command reference is not published as
  a dedicated cmdref page on docs.cilium.io/en/v1.20; rely on feature
  pages or the Cilium CLI repo.
- BGP shell subcommand help text (`cilium-dbg shell -- bgp/peers --help`)
  is not in rendered docs; subcommands were verified from source/bugtool.
- `CiliumEnvoyConfig` has no status conditions or CRD validation
  feedback; troubleshooting is agent-log only by design.
