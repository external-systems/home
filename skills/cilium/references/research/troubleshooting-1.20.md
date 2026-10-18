# Cilium 1.20 troubleshooting research

Official troubleshooting and operational reference for Cilium **1.20.x**.
All claims are cited to primary Cilium docs (rendered `v1.20` where a
version-pinned page exists) or to the Cilium source / CLI reference.

Scope: general agent/operator health, connectivity/datapath, policy/identity/endpoint, BGP v2, LoadBalancer IPAM, L2 announcements, Gateway API, Cluster Mesh, Envoy/L7/CiliumEnvoyConfig, Hubble, metrics, and upgrade/operations.

## URL legend

| Link style | Meaning |
|------------|---------|
| `v1.20` pinned | URL contains `/en/v1.20/` and was fetched successfully for 1.20.3. |
| Rolling stable | URL contains `/en/stable/`; use when the pinned page does not exist or when following upstream-only links (Gateway API CRDs, cert-manager, etc.). |

---

## 1. Version-pinned official documentation URL map

| Topic | v1.20 pinned URL | Rolling stable URL |
|-------|------------------|--------------------|
| Main troubleshooting guide | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) | [stable operations/troubleshooting](https://docs.cilium.io/en/stable/operations/troubleshooting/) |
| Upgrade guide | [v1.20 operations/upgrade](https://docs.cilium.io/en/v1.20/operations/upgrade/) | [stable operations/upgrade](https://docs.cilium.io/en/stable/operations/upgrade/) |
| BGP control plane - operation | [v1.20 network/bgp-control-plane/bgp-control-plane-operation](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) | [stable ...bgp-control-plane-operation](https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane-operation/) |
| BGP control plane - troubleshooting | [v1.20 network/bgp-control-plane/bgp-control-plane-troubleshooting](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/) | [stable ...bgp-control-plane-troubleshooting](https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane-troubleshooting/) |
| LoadBalancer IPAM | [v1.20 network/lb-ipam](https://docs.cilium.io/en/v1.20/network/lb-ipam/) | [stable network/lb-ipam](https://docs.cilium.io/en/stable/network/lb-ipam/) |
| L2 announcements (beta) | [v1.20 network/l2-announcements](https://docs.cilium.io/en/v1.20/network/l2-announcements/) | [stable network/l2-announcements](https://docs.cilium.io/en/stable/network/l2-announcements/) |
| Cluster Mesh setup (includes troubleshooting section) | [v1.20 network/clustermesh/setup](https://docs.cilium.io/en/v1.20/network/clustermesh/setup/) | [stable network/clustermesh/setup](https://docs.cilium.io/en/stable/network/clustermesh/setup/) |
| Ingress | [v1.20 network/servicemesh/ingress](https://docs.cilium.io/en/v1.20/network/servicemesh/ingress/) | [stable network/servicemesh/ingress](https://docs.cilium.io/en/stable/network/servicemesh/ingress/) |
| L7 traffic management / CiliumEnvoyConfig caveats | [v1.20 network/servicemesh/l7-traffic-management](https://docs.cilium.io/en/v1.20/network/servicemesh/l7-traffic-management/) | [stable network/servicemesh/l7-traffic-management](https://docs.cilium.io/en/stable/network/servicemesh/l7-traffic-management/) |
| Gateway API | [v1.20 network/servicemesh/gateway-api/gateway-api](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/gateway-api/) | [stable ...gateway-api/gateway-api](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/) |
| Gateway API troubleshooting | [v1.20 network/servicemesh/gateway-api/troubleshooting](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/) | [stable ...gateway-api/troubleshooting](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/troubleshooting/) |
| Hubble setup / troubleshooting | [v1.20 observability/hubble/setup](https://docs.cilium.io/en/v1.20/observability/hubble/setup/) | [stable observability/hubble/setup](https://docs.cilium.io/en/stable/observability/hubble/setup/) |
| Hubble TLS | [v1.20 observability/hubble/configuration/tls](https://docs.cilium.io/en/v1.20/observability/hubble/configuration/tls/) | [stable ...hubble/configuration/tls](https://docs.cilium.io/en/stable/observability/hubble/configuration/tls/) |
| Metrics reference | [v1.20 observability/metrics](https://docs.cilium.io/en/v1.20/observability/metrics/) | [stable observability/metrics](https://docs.cilium.io/en/stable/observability/metrics/) |
| `cilium-dbg status` cmdref | [v1.20 cmdref/cilium-dbg_status](https://docs.cilium.io/en/v1.20/cmdref/cilium-dbg_status/) | [stable cmdref/cilium-dbg_status](https://docs.cilium.io/en/stable/cmdref/cilium-dbg_status/) |
| `cilium-dbg config` cmdref | [v1.20 cmdref/cilium-dbg_config](https://docs.cilium.io/en/v1.20/cmdref/cilium-dbg_config/) | [stable cmdref/cilium-dbg_config](https://docs.cilium.io/en/stable/cmdref/cilium-dbg_config/) |
| `cilium-dbg shell` cmdref | [v1.20 cmdref/cilium-dbg_shell](https://docs.cilium.io/en/v1.20/cmdref/cilium-dbg_shell/) | [stable cmdref/cilium-dbg_shell](https://docs.cilium.io/en/stable/cmdref/cilium-dbg_shell/) |

Included sections (same rendered page as main troubleshooting):

| Included section | Anchor on the main troubleshooting page |
|------------------|------------------------------------------|
| Cluster Mesh troubleshooting | `#cluster-mesh-troubleshooting` on [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#cluster-mesh-troubleshooting) |
| Service Mesh / Ingress / CiliumEnvoyConfig troubleshooting | `#service-mesh-troubleshooting` on [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#service-mesh-troubleshooting) |

---

## 2. Symptom-to-first-doc / decision table

Use this table to pick the first official doc to read for a given symptom.
Each row cites the source used to map the symptom.

| Symptom / observation | First doc to open | Why this doc |
|-----------------------|-------------------|--------------|
| Cilium pods CrashLoopBackOff, `cilium-dbg status` unhealthy, controller failures, general cluster health unknown | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) | Covers Kubernetes/generic health, `cilium-dbg status`, logs, `cilium-health`, `cilium-dbg monitor`, sysdump [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/). |
| Pod-to-pod works on one node but fails across nodes; `cilium-health` shows unreachable nodes; packet drops in `cilium-dbg monitor` | [v1.20 operations/troubleshooting - Connectivity Problems](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#connectivity-problems) | Datapath-specific steps: `cilium-health status --verbose`, `cilium-dbg monitor --type drop`, overlay/native-routing checks, conntrack GC [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/). |
| Traffic unexpectedly blocked by policy; need to know which rules apply to an endpoint; FQDN policy not working | [v1.20 security/policy/troubleshooting](https://docs.cilium.io/en/v1.20/security/policy/troubleshooting/) | Maps `cilium-dbg endpoint get`/`policy get`, FQDN cache, identity exhaustion [[2]](https://docs.cilium.io/en/v1.20/security/policy/troubleshooting/). |
| Pods not managed by Cilium; `Cluster Pods: N/M managed by Cilium` shows missing pods | [v1.20 operations/troubleshooting - Ensure pod is managed by Cilium](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#ensure-managed-pod) | Lists host-network and pre-Cilium pod causes; points to `k8s-unmanaged.sh` [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/). |
| `CiliumBGPClusterConfig` applied but no `CiliumBGPNodeConfig`; BGP session not `established`; routes missing after session up | [v1.20 network/bgp-control-plane/bgp-control-plane-troubleshooting](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/) | Condition-based quick diagnosis: `NoMatchingNode`, `ConflictingClusterConfig`, `MissingPeerConfigs`, `MissingAuthSecret` [[3]](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/). |
| Need to drain/shutdown a BGP node, plan graceful restart, understand route-withdrawal timing, or recover from agent restart | [v1.20 network/bgp-control-plane/bgp-control-plane-operation](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) | Covers shutdown dance, graceful-restart trade-offs, failure scenarios, operator-down impact [[4]](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/). |
| LoadBalancer Service stays `<pending>`; conflicting IP pools; VIPs changed after pool update | [v1.20 network/lb-ipam](https://docs.cilium.io/en/v1.20/network/lb-ipam/) | Pool conflicts, service selectors, `io.cilium/lb-ipam-request-satisfied` conditions, sharing keys [[5]](https://docs.cilium.io/en/v1.20/network/lb-ipam/). |
| ARP/NDP for Service VIP not answered; L2 announcement lease flapping; client cannot reach VIP on local L2 | [v1.20 network/l2-announcements](https://docs.cilium.io/en/v1.20/network/l2-announcements/) | Step-by-step: feature flags, leases, `cilium-dbg shell -- db/show l2-announce`, ARP test, BPF map check [[6]](https://docs.cilium.io/en/v1.20/network/l2-announcements/). |
| Gateway API: Gateway not `Programmed`; no address; HTTPRoute not attached; backend service not found | [v1.20 network/servicemesh/gateway-api/troubleshooting](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/) | Checks Gateway/HTTPRoute conditions, operator logs for missing CRDs, common mistakes [[7]](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/). |
| Ingress returns 503 / `no healthy upstream`; Envoy proxy port unreachable; CiliumEnvoyConfig conflict | [v1.20 operations/troubleshooting - Service Mesh Troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#service-mesh-troubleshooting) | Validates kube-proxy replacement, Envoy config, generated Service/CEC, backend EDS, Hubble flows [[8]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_servicemesh.rst). |
| CiliumEnvoyConfig applied silently but Envoy ignores it; need to know validation limitations | [v1.20 network/servicemesh/l7-traffic-management](https://docs.cilium.io/en/v1.20/network/servicemesh/l7-traffic-management/) | Documents minimal validation, no conflict resolution, annotation requirements for east-west CECs [[9]](https://docs.cilium.io/en/v1.20/network/servicemesh/l7-traffic-management/). |
| Cluster Mesh not ready; remote nodes/identities/services missing; TLS errors between clustermesh-apiservers | [v1.20 network/clustermesh/setup - Troubleshooting](https://docs.cilium.io/en/v1.20/network/clustermesh/setup/#troubleshooting) and [main troubleshooting Cluster Mesh section](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#cluster-mesh-troubleshooting) | Automatic (`cilium-dbg troubleshoot clustermesh`) and manual verification, state propagation, TLS cert checks [[10]](https://docs.cilium.io/en/v1.20/network/clustermesh/setup/), [[11]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_clustermesh.rst). |
| Hubble Relay not ready; `cilium status` shows Hubble errors; no flows via `hubble observe` | [v1.20 observability/hubble/setup](https://docs.cilium.io/en/v1.20/observability/hubble/setup/) | Deployment validation, Relay/agent pod logs, port-forward, metrics misconfiguration [[12]](https://docs.cilium.io/en/v1.20/observability/hubble/setup/). |
| Hubble TLS handshake failures; cert-manager webhook errors; expired Hubble certs | [v1.20 observability/hubble/configuration/tls](https://docs.cilium.io/en/v1.20/observability/hubble/configuration/tls/) | TLS enablement, cert methods, troubleshooting, validation with `hubble watch peers` and OpenSSL [[13]](https://docs.cilium.io/en/v1.20/observability/hubble/configuration/tls/). |
| Upgrade failure; pre-flight check fails; invalid CiliumNetworkPolicy; need rollback steps | [v1.20 operations/upgrade](https://docs.cilium.io/en/v1.20/operations/upgrade/) | Pre-flight, `upgradeCompatibility`, CNP validator, version-specific notes, rollback [[14]](https://docs.cilium.io/en/v1.20/operations/upgrade/). |
| Need metric names for alerting (BGP state, LB IPAM saturation, policy map pressure, drops, etc.) | [v1.20 observability/metrics](https://docs.cilium.io/en/v1.20/observability/metrics/) | Full agent/operator/Hubble/clustermesh metric tables [[15]](https://docs.cilium.io/en/v1.20/observability/metrics/). |

---

## 3. Verified diagnostic commands

Commands are grouped by area. Each row states what the command establishes and cites the source.

### 3.1 General agent / operator health

| Command | What it establishes | Source |
|---------|---------------------|--------|
| `kubectl -n kube-system get pods -l k8s-app=cilium` | Quick liveness: all agents Running? CrashLoopBackOff indicates permanent failure reported via `cilium-dbg status` / liveness probe. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `kubectl -n kube-system exec <cilium-pod> -- cilium-dbg status [--verbose]` | Detailed agent health: KVStore, Kubernetes API, Cilium, NodeMonitor, health daemon, controller status, proxy status, cluster health, IPAM, Hubble. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `cilium status` (Cilium CLI) | Cluster-wide summary: Cilium/Operator/Hubble/ClusterMesh health, DaemonSet/Deployment readiness, managed pod count, image versions. | [v1.20 observability/hubble/setup](https://docs.cilium.io/en/v1.20/observability/hubble/setup/) [[12]](https://docs.cilium.io/en/v1.20/observability/hubble/setup/) |
| `kubectl -n kube-system logs --timestamps [-p] <cilium-pod>` | Current or previous container logs. Use `-p` after a restart caused by liveness failure. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `kubectl -n kube-system exec ds/cilium -- cilium-dbg config --all \| grep <OPTION>` | Runtime configuration value (e.g. `EnableL2Announcements`, `KubeProxyReplacement`, `EnableExternalIPs`). | [v1.20 network/l2-announcements](https://docs.cilium.io/en/v1.20/network/l2-announcements/) [[6]](https://docs.cilium.io/en/v1.20/network/l2-announcements/) |
| `kubectl -n kube-system get cm cilium-config -o json \| egrep 'enable-ingress-controller\|enable-envoy-config\|kube-proxy-replacement'` | Helm values reflected in the ConfigMap for Ingress/Envoy/kube-proxy replacement. | [v1.20 operations/troubleshooting - Service Mesh Troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#service-mesh-troubleshooting) [[8]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_servicemesh.rst) |
| `cilium-dbg debuginfo -f debuginfo.md` | Markdown-formatted agent debug dump (included automatically in `cilium sysdump`). Strip sensitive data before sharing. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |

### 3.2 Connectivity and datapath

| Command | What it establishes | Source |
|---------|---------------------|--------|
| `kubectl -n kube-system exec -ti <cilium-pod> -- cilium-health status --verbose` | Bidirectional ICMP/HTTP health matrix to every node and a simulated endpoint on each node. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `kubectl -n kube-system exec -ti <cilium-pod> -- cilium-dbg monitor --type drop` | Live dropped packets with reason (e.g. `Policy denied`, `Invalid destination mac`). | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `kubectl -n kube-system exec ds/cilium -- cilium-dbg bpf ipcache list` | IP cache entries (local + remote Cluster Mesh). Used to verify tunnel endpoint or routing target for cross-node traffic. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `tcpdump -n -i cilium_vxlan` (on node) | Whether encapsulated cross-node traffic is forwarded between nodes (overlay mode). | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `cilium-dbg monitor --type drop` showing `CT: Map insertion failed` | Connection-tracking table pressure. Remedies: lower `--conntrack-gc-interval`, raise `bpf-ct-global-any-max` / `bpf-ct-global-tcp-max`; track via `datapath_conntrack_gc_*` metrics. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `cilium connectivity test [--multi-cluster <ctx2>]` | Deploys echo pods and CNPs to exercise pod-to-pod, pod-to-service, NodePort, policy, and external paths. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/), [Cluster Mesh setup](https://docs.cilium.io/en/v1.20/network/clustermesh/setup/) [[10]](https://docs.cilium.io/en/v1.20/network/clustermesh/setup/) |

### 3.3 Policy / identity / endpoint

| Command | What it establishes | Source |
|---------|---------------------|--------|
| `kubectl -n kube-system exec -ti <cilium-pod> -- cilium-dbg endpoint list` | Endpoints on the node, their IDs, states, and identities. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `kubectl -n kube-system exec -ti <cilium-pod> -- cilium-dbg endpoint get <endpoint-id>` | Full desired (`spec`) and realized (`status.policy.realized.l4`) policy for one endpoint; `derived-from-rules` points to the originating rules. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `cilium-dbg endpoint get <id> -o jsonpath='...derived-from-rules...' \| tr -d '][' \| xargs -I{} cilium-dbg policy get {}` | Maps an endpoint back to the exact CNP/CCNP rules selecting it. | [v1.20 security/policy/troubleshooting](https://docs.cilium.io/en/v1.20/security/policy/troubleshooting/) [[2]](https://docs.cilium.io/en/v1.20/security/policy/troubleshooting/) |
| `cilium-dbg fqdn cache list` | FQDN-to-IP mappings learned from DNS; required before `toFQDNs` rules take effect. | [v1.20 security/policy/troubleshooting](https://docs.cilium.io/en/v1.20/security/policy/troubleshooting/) [[2]](https://docs.cilium.io/en/v1.20/security/policy/troubleshooting/) |
| `cilium-dbg ip list \| grep <IP>` | Whether a DNS-observed IP has a local identity (`fqdn:...`). | [v1.20 security/policy/troubleshooting](https://docs.cilium.io/en/v1.20/security/policy/troubleshooting/) [[2]](https://docs.cilium.io/en/v1.20/security/policy/troubleshooting/) |
| `cilium-dbg policy selectors` | Which selectors select many identities (policymap pressure). Types: Label, CIDR, FQDN. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `cilium-dbg identity list` | Allocated security identities (useful in Cluster Mesh to verify remote identities). | [v1.20 operations/troubleshooting - Cluster Mesh](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#cluster-mesh-troubleshooting) [[11]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_clustermesh.rst) |

### 3.4 BGP v2 control plane

| Command | What it establishes | Source |
|---------|---------------------|--------|
| `kubectl get ciliumbgpnodeconfigs` | Per-node live BGP config generated by the operator from `CiliumBGPClusterConfig`. | [v1.20 network/bgp-control-plane/bgp-control-plane-operation](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) [[4]](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) |
| `kubectl describe ciliumbgpnodeconfigs <node>` | Real-time instance state, peers, `PeeringState`, `RouteCount`, applied timers. | [v1.20 network/bgp-control-plane/bgp-control-plane-operation](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) [[4]](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) |
| `cilium bgp peers` (Cilium CLI) | Cluster-wide BGP peering state, session state, uptime, family, received/advertised counts. | [v1.20 network/bgp-control-plane/bgp-control-plane-operation](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) [[4]](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) |
| `cilium bgp routes available ipv4 unicast` | Local BGP RIB (available routes). | [v1.20 network/bgp-control-plane/bgp-control-plane-operation](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) [[4]](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) |
| `cilium bgp routes advertised ipv4 unicast` | Per-peer advertised routes and attributes (communities, AS path, MP_REACH). | [v1.20 network/bgp-control-plane/bgp-control-plane-operation](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) [[4]](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) |
| `kubectl -n kube-system exec <cilium-pod> -- cilium-dbg shell -- bgp/peers [-f detailed]` | **Preferred in 1.20** after deprecation of `cilium-dbg bgp peers`. | Cilium source / upgrade notes [[16]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/upgrade-current.inc) |
| `kubectl -n kube-system exec <cilium-pod> -- cilium-dbg shell -- bgp/routes [-a] in\|out <afi> <safi>` | **Preferred in 1.20** replacement for `cilium bgp routes ...`. Examples: `bgp/routes -a in ipv4 unicast`, `bgp/routes out ipv4 unicast -a`. | Cilium source / bugtool [[17]](https://github.com/cilium/cilium/blob/main/bugtool/cmd/configuration.go) |
| `kubectl -n kube-system exec <cilium-pod> -- cilium-dbg shell -- bgp/route-policies` | **Preferred in 1.20** replacement for `cilium-dbg bgp route-policies`. | Cilium source [[18]](https://github.com/cilium/cilium/blob/main/cilium-dbg/cmd/bgp_route_policy_get.go) |
| `kubectl -n kube-system logs <cilium-agent> \| grep subsys=bgp-control-plane` | Agent-side BGP errors (ASN mismatch, capability mismatch, peer IP wrong, MD5 issues). | [v1.20 network/bgp-control-plane/bgp-control-plane-troubleshooting](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/) [[3]](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/) |
| `kubectl -n kube-system logs <cilium-operator> \| grep subsys=bgp-cp-operator` | Operator-side errors translating `CiliumBGPClusterConfig` to `CiliumBGPNodeConfig`. | [v1.20 network/bgp-control-plane/bgp-control-plane-operation](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) [[4]](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) |

### 3.5 LoadBalancer IPAM and L2 announcements

| Command | What it establishes | Source |
|---------|---------------------|--------|
| `kubectl get ippools` | Pool state: `DISABLED`, `CONFLICTING`, available IPs. | [v1.20 network/lb-ipam](https://docs.cilium.io/en/v1.20/network/lb-ipam/) [[5]](https://docs.cilium.io/en/v1.20/network/lb-ipam/) |
| `kubectl get ippools/<pool> -o jsonpath='{.status.conditions[?(@.type=="cilium.io/PoolConflict")].message}'` | Reason for a conflicting pool (overlapping CIDR). | [v1.20 network/lb-ipam](https://docs.cilium.io/en/v1.20/network/lb-ipam/) [[5]](https://docs.cilium.io/en/v1.20/network/lb-ipam/) |
| `kubectl get svc/<svc> -o jsonpath='{.status.conditions}'` | Service LB IPAM condition `io.cilium/lb-ipam-request-satisfied` (reasons: `no_pool`, `satisfied`). | [v1.20 network/lb-ipam](https://docs.cilium.io/en/v1.20/network/lb-ipam/) [[5]](https://docs.cilium.io/en/v1.20/network/lb-ipam/) |
| `kubectl -n kube-system exec ds/cilium -- cilium-dbg config --all \| grep -E 'EnableL2Announcements\|KubeProxyReplacement\|EnableExternalIPs'` | Feature prerequisites for L2 announcements. | [v1.20 network/l2-announcements](https://docs.cilium.io/en/v1.20/network/l2-announcements/) [[6]](https://docs.cilium.io/en/v1.20/network/l2-announcements/) |
| `kubectl get CiliumL2AnnouncementPolicy` | Policies exist and are configured. | [v1.20 network/l2-announcements](https://docs.cilium.io/en/v1.20/network/l2-announcements/) [[6]](https://docs.cilium.io/en/v1.20/network/l2-announcements/) |
| `kubectl -n kube-system get lease \| grep cilium-l2announce` | Per-service leader-election leases; holder = node currently answering ARP/NDP. | [v1.20 network/l2-announcements](https://docs.cilium.io/en/v1.20/network/l2-announcements/) [[6]](https://docs.cilium.io/en/v1.20/network/l2-announcements/) |
| `kubectl -n kube-system exec <holder-agent> -- cilium-dbg shell -- db/show l2-announce` | Agent's internal L2 announce state: IP -> network interface. | [v1.20 network/l2-announcements](https://docs.cilium.io/en/v1.20/network/l2-announcements/) [[6]](https://docs.cilium.io/en/v1.20/network/l2-announcements/) |
| `kubectl -n kube-system exec ds/cilium -- cilium-dbg shell -- db/show devices` | Device list with `Selected` flag; L2 announcements only work on selected devices. | [v1.20 network/l2-announcements](https://docs.cilium.io/en/v1.20/network/l2-announcements/) [[6]](https://docs.cilium.io/en/v1.20/network/l2-announcements/) |
| `bpftool map dump pinned /sys/fs/bpf/tc/globals/cilium_l2_responder_v4` | BPF ARP responder counters (`responses_sent`) to confirm ARP requests reach the datapath. | [v1.20 network/l2-announcements](https://docs.cilium.io/en/v1.20/network/l2-announcements/) [[6]](https://docs.cilium.io/en/v1.20/network/l2-announcements/) |

### 3.6 Gateway API / Ingress / CiliumEnvoyConfig

| Command | What it establishes | Source |
|---------|---------------------|--------|
| `kubectl get gateway -A` | Gateway class, address, `PROGRAMMED` status. Cilium only programs class `cilium`. | [v1.20 network/servicemesh/gateway-api/troubleshooting](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/) [[7]](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/) |
| `kubectl describe gateway <name>` | Gateway/listener conditions: `Accepted`, `Programmed`, `ResolvedRefs`; attached route count. | [v1.20 network/servicemesh/gateway-api/troubleshooting](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/) [[7]](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/) |
| `kubectl describe httproute <name>` | Parent conditions: `Accepted`, `ResolvedRefs` (e.g. `BackendNotFound`). | [v1.20 network/servicemesh/gateway-api/troubleshooting](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/) [[7]](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/) |
| `kubectl logs -n kube-system deployments/cilium-operator \| grep gateway` | Missing Gateway API CRDs or controller errors. | [v1.20 network/servicemesh/gateway-api/troubleshooting](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/) [[7]](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/) |
| `kubectl get ingress` / `kubectl get cec <name>` / `kubectl get svc cilium-ingress[-<name>]` | Ingress generated LoadBalancer Service and `CiliumEnvoyConfig` (dedicated vs shared mode). | [v1.20 operations/troubleshooting - Service Mesh Troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#service-mesh-troubleshooting) [[8]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_servicemesh.rst) |
| `curl -v http://localhost:<NodePort>/` from a node | Whether traffic reaches the Envoy proxy (`server: envoy` header). | [v1.20 operations/troubleshooting - Service Mesh Troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#service-mesh-troubleshooting) [[8]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_servicemesh.rst) |
| `kubectl -n kube-system exec ds/cilium -- hubble observe --identity 2\|8 -f` | Flows for `world` (identity 2) and `ingress` (identity 8) to see policy drops and proxy forwarding. | [v1.20 operations/troubleshooting - Service Mesh Troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#service-mesh-troubleshooting) [[8]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_servicemesh.rst) |
| `kubectl -n kube-system logs ds/cilium --timestamps \| egrep 'envoy\|proxy'` | Proxy port assigned by the Ingress controller for direct-to-Envoy testing. | [v1.20 operations/troubleshooting - Service Mesh Troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#service-mesh-troubleshooting) [[8]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_servicemesh.rst) |

### 3.7 Cluster Mesh

| Command | What it establishes | Source |
|---------|---------------------|--------|
| `cilium clustermesh status --wait` | Cluster Mesh control plane health and node connection counts. | [v1.20 network/clustermesh/setup](https://docs.cilium.io/en/v1.20/network/clustermesh/setup/) [[10]](https://docs.cilium.io/en/v1.20/network/clustermesh/setup/) |
| `kubectl exec -it -n kube-system ds/cilium -c cilium-agent -- cilium-dbg troubleshoot clustermesh` | Automatic checks: DNS, connectivity, TLS auth, etcd auth for agent -> KVStoreMesh/remote clusters. | [v1.20 operations/troubleshooting - Cluster Mesh Troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#cluster-mesh-troubleshooting) [[11]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_clustermesh.rst) |
| `kubectl exec -it -n kube-system deploy/clustermesh-apiserver -c kvstoremesh -- clustermesh-apiserver kvstoremesh-dbg troubleshoot` | KVStoreMesh -> remote cluster control-plane checks. | [v1.20 operations/troubleshooting - Cluster Mesh Troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#cluster-mesh-troubleshooting) [[11]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_clustermesh.rst) |
| `kubectl -n kube-system exec ds/cilium -- cilium-dbg status --all-clusters` | Remote clusters ready, etcd connection, sync status (nodes, endpoints, identities, services). | [v1.20 operations/troubleshooting - Cluster Mesh Troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#cluster-mesh-troubleshooting) [[11]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_clustermesh.rst) |
| `kubectl -n kube-system exec ds/cilium -- cilium-dbg node list` | Local + remote nodes present. | [v1.20 operations/troubleshooting - Cluster Mesh Troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#cluster-mesh-troubleshooting) [[11]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_clustermesh.rst) |
| `kubectl -n kube-system exec ds/cilium -- cilium-dbg bpf ipcache list` | IP cache contains remote pod IPs. | [v1.20 operations/troubleshooting - Cluster Mesh Troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#cluster-mesh-troubleshooting) [[11]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_clustermesh.rst) |
| `kubectl -n kube-system exec ds/cilium -- cilium-dbg shell -- db/show backends` (or `cilium-dbg service list`) | Global service backends from all clusters. | [v1.20 operations/troubleshooting - Cluster Mesh Troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#cluster-mesh-troubleshooting) [[11]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_clustermesh.rst) |
| `kubectl -n kube-system logs deployment/clustermesh-apiserver -c apiserver` | etcd session establishment for the local clustermesh-apiserver. | [v1.20 operations/troubleshooting - Cluster Mesh Troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#cluster-mesh-troubleshooting) [[11]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_clustermesh.rst) |
| `kubectl -n kube-system exec ds/cilium -c cilium-agent -- ls /var/lib/cilium/clustermesh` | Mounted peer configuration files (one per remote cluster). | [v1.20 operations/troubleshooting - Cluster Mesh Troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#cluster-mesh-troubleshooting) [[11]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_clustermesh.rst) |

### 3.8 Hubble

| Command | What it establishes | Source |
|---------|---------------------|--------|
| `cilium status` | Hubble Relay and Hubble agent health. | [v1.20 observability/hubble/setup](https://docs.cilium.io/en/v1.20/observability/hubble/setup/) [[12]](https://docs.cilium.io/en/v1.20/observability/hubble/setup/) |
| `kubectl -n kube-system get pods -l k8s-app=cilium` / `-l k8s-app=hubble-relay` | Pod readiness of agent and Relay. | [v1.20 observability/hubble/setup](https://docs.cilium.io/en/v1.20/observability/hubble/setup/) [[12]](https://docs.cilium.io/en/v1.20/observability/hubble/setup/) |
| `kubectl -n kube-system logs <hubble-relay-pod>` | Relay connection errors to `hubble-peer` service (e.g. TLS, connection refused). | [v1.20 observability/hubble/setup](https://docs.cilium.io/en/v1.20/observability/hubble/setup/) [[12]](https://docs.cilium.io/en/v1.20/observability/hubble/setup/) |
| `kubectl logs -n kube-system -c cilium-agent -l k8s-app=cilium --tail=-1 \| grep subsys=hubble` | Agent-side Hubble startup errors (e.g. unknown metric). | [v1.20 observability/hubble/setup](https://docs.cilium.io/en/v1.20/observability/hubble/setup/) [[12]](https://docs.cilium.io/en/v1.20/observability/hubble/setup/) |
| `kubectl exec -n kube-system <cilium-pod> -- hubble status` | Local Hubble server health and flow ring buffer saturation. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `hubble status -P` / `hubble observe -P` | Cluster-wide flow access via Relay (with automatic port-forward). | [v1.20 observability/hubble/setup](https://docs.cilium.io/en/v1.20/observability/hubble/setup/) [[12]](https://docs.cilium.io/en/v1.20/observability/hubble/setup/) |
| `hubble list nodes -P` | Nodes connected to Relay and flow rates. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `kubectl exec -it -n kube-system deployment/hubble-cli -- hubble watch peers --server unix:///var/run/cilium/hubble.sock` | TLS-enabled peer list with `TLS.ServerName` (missing name = TLS disabled). | [v1.20 observability/hubble/configuration/tls](https://docs.cilium.io/en/v1.20/observability/hubble/configuration/tls/) [[13]](https://docs.cilium.io/en/v1.20/observability/hubble/configuration/tls/) |

### 3.9 Sysdump / bugtool

| Command | What it establishes | Source |
|---------|---------------------|--------|
| `cilium sysdump` | Collects logs and state from all nodes for support. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `cilium sysdump --node-list <nodes> --logs-since-time <time> --logs-limit-bytes <bytes>` | Limits size on clusters >20 nodes; preferred over full dump. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `kubectl -n kube-system exec <cilium-pod> -- cilium-bugtool` | Single-node debug archive (run inside agent pod). | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |

---

## 4. Important status conditions, log locations, and metrics

### 4.1 CRD status conditions

| Resource | Condition | Meaning | Source |
|----------|-----------|---------|--------|
| `CiliumBGPClusterConfig` | `cilium.io/NoMatchingNode` | `nodeSelector` matches no nodes. | [v1.20 BGP troubleshooting](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/) [[3]](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/) |
| `CiliumBGPClusterConfig` | `cilium.io/ConflictingClusterConfig` | Another `CiliumBGPClusterConfig` selects the same node. | [v1.20 BGP troubleshooting](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/) [[3]](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/) |
| `CiliumBGPClusterConfig` | `cilium.io/MissingPeerConfigs` | A referenced `CiliumBGPPeerConfig` does not exist. | [v1.20 BGP troubleshooting](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/) [[3]](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/) |
| `CiliumBGPPeerConfig` | `cilium.io/MissingAuthSecret` | Referenced MD5 auth Secret is missing; session proceeds with empty password. | [v1.20 BGP troubleshooting](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/) [[3]](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/) |
| `CiliumLoadBalancerIPPool` | `cilium.io/PoolConflict` | Overlapping CIDR with another pool; last-added pool stops allocating. | [v1.20 LB IPAM](https://docs.cilium.io/en/v1.20/network/lb-ipam/) [[5]](https://docs.cilium.io/en/v1.20/network/lb-ipam/) |
| `CiliumLoadBalancerIPPool` | `cilium.io/IPsTotal` / `IPsAvailable` / `IPsUsed` | Pool capacity counters. | [v1.20 LB IPAM](https://docs.cilium.io/en/v1.20/network/lb-ipam/) [[5]](https://docs.cilium.io/en/v1.20/network/lb-ipam/) |
| `Service` (type LoadBalancer) | `io.cilium/lb-ipam-request-satisfied` | `True` reason `satisfied` or `False` reason `no_pool` / etc. | [v1.20 LB IPAM](https://docs.cilium.io/en/v1.20/network/lb-ipam/) [[5]](https://docs.cilium.io/en/v1.20/network/lb-ipam/) |
| `CiliumL2AnnouncementPolicy` | `io.cilium/bad-service-selector` | Invalid selector expression. | [v1.20 L2 announcements](https://docs.cilium.io/en/v1.20/network/l2-announcements/) [[6]](https://docs.cilium.io/en/v1.20/network/l2-announcements/) |
| `Gateway` | `Accepted` / `Programmed` / `ResolvedRefs` | Gateway scheduled, programmed into Envoy, secrets resolved. | [v1.20 Gateway API troubleshooting](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/) [[7]](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/) |
| `HTTPRoute` | `Accepted` / `ResolvedRefs` | Route accepted; backend service references valid. | [v1.20 Gateway API troubleshooting](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/) [[7]](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/) |

### 4.2 Log locations and key subsystems

| Component | Log filter / location | Use | Source |
|-----------|----------------------|-----|--------|
| Cilium agent | `subsys=bgp-control-plane` | BGP session errors (ASN mismatch, capability mismatch, MD5 timeout). | [v1.20 BGP troubleshooting](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/) [[3]](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/) |
| Cilium operator | `subsys=bgp-cp-operator` | Translation of `CiliumBGPClusterConfig` to `CiliumBGPNodeConfig`. | [v1.20 BGP operation](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) [[4]](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) |
| Cilium operator | `subsys=gateway-api` | Missing Gateway API CRDs or controller errors. | [v1.20 Gateway API troubleshooting](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/) [[7]](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/) |
| Cilium agent | `subsys=hubble` | Hubble startup/metric errors. | [v1.20 Hubble setup](https://docs.cilium.io/en/v1.20/observability/hubble/setup/) [[12]](https://docs.cilium.io/en/v1.20/observability/hubble/setup/) |
| Cilium agent | `subsys=klog` + leases | L2-announcement Kubernetes lease throttling or RBAC errors. | [v1.20 L2 announcements](https://docs.cilium.io/en/v1.20/network/l2-announcements/) [[6]](https://docs.cilium.io/en/v1.20/network/l2-announcements/) |
| clustermesh-apiserver | `subsys=kvstore` | etcd session, quorum, and remote-cluster sync errors. | [v1.20 Cluster Mesh troubleshooting](https://docs.cilium.io/en/v1.20/network/clustermesh/setup/#troubleshooting) [[10]](https://docs.cilium.io/en/v1.20/network/clustermesh/setup/) |
| Cilium agent | `msg="Connection to remote cluster established"` / `msg="Unable to establish etcd connection to remote cluster"` | Cluster Mesh agent->KVStoreMesh/remote cluster connectivity. | [v1.20 operations/troubleshooting - Cluster Mesh](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#cluster-mesh-troubleshooting) [[11]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_clustermesh.rst) |

### 4.3 Key metrics

All metric names and descriptions are taken from the [v1.20 metrics reference](https://docs.cilium.io/en/v1.20/observability/metrics/) [[15]](https://docs.cilium.io/en/v1.20/observability/metrics/).

#### Agent / datapath

| Metric | Labels / notes | When to watch |
|--------|----------------|---------------|
| `cilium_drop_count_total` | `reason`, `direction` | Sudden spikes indicate policy, CT, or forwarding drops. |
| `cilium_forward_count_total` / `cilium_forward_bytes_total` | `direction` | Baseline forwarding health. |
| `cilium_bpf_map_pressure{map_name="cilium_policy_v3_*"}` | `map_name` | Policymap pressure near/above 1.0 indicates identity explosion or overly permissive selectors. |
| `cilium_datapath_conntrack_gc_entries` | `family`, `protocol`, `status` | Conntrack table size and GC effectiveness. |
| `cilium_node_health_connectivity_status` / `cilium_node_health_connectivity_latency_seconds` | Node health matrix. | High-cardinality; consider disabling on very large clusters. |

#### Policy / identity

| Metric | Labels / notes | When to watch |
|--------|----------------|---------------|
| `cilium_policy` | Number of policies loaded. | Unexpected counts after policy changes. |
| `cilium_policy_change_total` | `source`, `operation`, `outcome` | Failing policy updates. |
| `cilium_policy_implementation_delay` | `source` | Time from policy change to datapath deployment. |
| `cilium_policy_missing_proxy_redirects` | Proxy redirects missing during endpoint regeneration. | L7 policy enforcement gaps. |
| `cilium_identity_label_sources{type="fqdn"}` | FQDN identity growth. | Compare with `cilium_fqdn_selectors` to detect identity exhaustion. |
| `cilium_endpoint_component_status` | `type`, `status` (`BPF`, `Policy`; `OK`/`Warning`/`Failure`) | Per-endpoint component health. |

#### BGP control plane

| Metric | Labels / notes | When to watch |
|--------|----------------|---------------|
| `cilium_bgp_control_plane_session_state` | `instance_name`, `local_asn`, `neighbor`, `neighbor_asn`; `1` = Up, `0` = Down. | Session flaps. |
| `cilium_bgp_control_plane_advertised_routes` | `instance_name`, `local_asn`, `neighbor`, `neighbor_asn`, `afi`, `safi`. | Verify expected prefix counts are advertised. |
| `cilium_bgp_control_plane_received_routes` | Same labels. | Verify received prefixes from peer. |
| `cilium_bgp_control_plane_reconcile_errors_total` | `instance_name` (agent) or `resource_kind`, `resource_name` (operator). | Failing BGP resource reconciliation. |

#### LB IPAM

> Exported under `cilium_` namespace, not `cilium_operator_`.

| Metric | When to watch |
|--------|---------------|
| `cilium_lbipam_conflicting_pools` | Non-zero means overlapping pools. |
| `cilium_lbipam_ips_available` / `cilium_lbipam_ips_used` | `pool` label; saturation per pool. |
| `cilium_lbipam_services_matching` / `cilium_lbipam_services_unsatisfied` | Unsatisfied > 0 means services not getting requested IPs. |

#### Cluster Mesh

| Metric | Namespace / notes | When to watch |
|--------|-------------------|---------------|
| `cilium_clustermesh_remote_clusters` | `cilium_` | Number of remote clusters meshed. |
| `cilium_clustermesh_remote_cluster_failures` | `cilium_`, `target_cluster` | Ongoing failures to a remote cluster. |
| `cilium_clustermesh_remote_cluster_readiness_status` | `cilium_`, `target_cluster` | Readiness per cluster. |
| `cilium_operator_clustermesh_remote_cluster_services` / `_endpoints` / `_endpoint_slices` | `cilium_operator_` | Propagated remote state counts. |

#### Hubble

| Metric | When to watch |
|--------|---------------|
| `hubble_lost_events_total` | `source` = perf ring buffer, observer queue, Hubble ring buffer. |
| `hubble_flows_processed_total` | `protocol`, `type`, `subtype`, `verdict`. |
| `hubble_drop_total` | `reason`, `protocol`. |

---

## 5. Safety notes for disruptive commands

| Command / operation | Risk | Mitigation | Source |
|---------------------|------|------------|--------|
| `cilium sysdump` | Collects logs from all nodes; on clusters >20 nodes can be very large and bandwidth-heavy. | Use `--node-list`, `--logs-since-time`, `--logs-limit-bytes`; prefer full history of selected nodes over brief history of all nodes. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `cilium-bugtool` | Archives system state including potentially sensitive data. | Review and strip sensitive info before sharing. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `kubectl drain <node> --ignore-daemonsets` | Evicts workloads. For BGP nodes, must be followed by nodeSelector flip and route-withdrawal wait. | Follow the BGP shutdown dance before powering off. | [v1.20 BGP operation](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) [[4]](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) |
| `kubectl label node <node> --overwrite enable-bgp=false` | Tears down all BGP sessions on the node. Traffic may still arrive until the peer withdraws routes. | Wait for peer withdrawal (immediate without GR, Stale Timer with RFC 8538 GR, or hold-time otherwise). | [v1.20 BGP operation](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) [[4]](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/) |
| `kubectl rollout undo daemonset/cilium -n kube-system` | Reverts Cilium DaemonSet after failed upgrade. | Check version-specific notes first; rolling back after new features were consumed can leave incompatible state. | [v1.20 operations/upgrade](https://docs.cilium.io/en/v1.20/operations/upgrade/) [[14]](https://docs.cilium.io/en/v1.20/operations/upgrade/) |
| `cilium connectivity test` | Deploys pods/policies into `cilium-test` namespace; may conflict with existing policies. | Only run in an isolated namespace with no other pods/policies. | [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) [[1]](https://docs.cilium.io/en/v1.20/operations/troubleshooting/) |
| `cilium preflight migrate-identity` | One-off kvstore->CRD identity migration; identities created after migration are not copied; rollback to kvstore is hard. | Run only during stable identity churn, or use "Double Write" mode for safer migration. | [v1.20 operations/upgrade](https://docs.cilium.io/en/v1.20/operations/upgrade/) [[14]](https://docs.cilium.io/en/v1.20/operations/upgrade/) |
| Updating `CiliumLoadBalancerIPPool` | Can reassign IPs and change Service VIPs. | Plan changes; check for conflicts first. | [v1.20 LB IPAM](https://docs.cilium.io/en/v1.20/network/lb-ipam/) [[5]](https://docs.cilium.io/en/v1.20/network/lb-ipam/) |
| `kubectl delete ciliumid --all` | Clears all CRD identities. | Only when no agent is running with `--identity-allocation-mode=crd`. | [v1.20 operations/upgrade](https://docs.cilium.io/en/v1.20/operations/upgrade/) [[14]](https://docs.cilium.io/en/v1.20/operations/upgrade/) |
| `debug-verbose=flow` + `debug=true` | Increases log volume and CPU load. | Enable only for targeted troubleshooting; revert after. | [v1.20 operations/troubleshooting - Service Mesh](https://docs.cilium.io/en/v1.20/operations/troubleshooting/#service-mesh-troubleshooting) [[8]](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_servicemesh.rst) |

---

## 6. Unresolved / follow-up items

1. **Rendered `cilium` (not `cilium-dbg`) CLI command reference** for `cilium status`, `cilium sysdump`, `cilium bgp`, `cilium clustermesh status`, etc. is not published under `docs.cilium.io/en/v1.20/cmdref/` as of this research. The Cilium docs embed command examples in feature pages (BGP, Cluster Mesh, Hubble, troubleshooting) but do not expose a dedicated `cilium` CLI cmdref. Use the feature pages above or the Cilium CLI repository for authoritative CLI help.
2. **Exact HTML anchors** for the included `troubleshooting_clustermesh.rst` and `troubleshooting_servicemesh.rst` sections on the main troubleshooting page are inferred from heading text (`#cluster-mesh-troubleshooting`, `#service-mesh-troubleshooting`). If the rendered Sphinx IDs differ, navigate via the page TOC.
3. **BGP shell command help text** (`cilium-dbg shell -- bgp/peers --help`, etc.) was not found in rendered docs; the subcommands `bgp/peers`, `bgp/routes`, `bgp/route-policies` were verified from Cilium source/bugtool only.
4. **Gateway API Inference Extension** (`gatewayAPI.inferenceExtention`) is mentioned as a new beta option in 1.20 upgrade notes but has no dedicated troubleshooting page yet.
5. **CiliumEnvoyConfig** has no status conditions or CRD validation feedback; the only official troubleshooting path is agent logs. This is documented as a known limitation, not an oversight.

---

## References (short list)

1. [v1.20 operations/troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/)
2. [v1.20 security/policy/troubleshooting](https://docs.cilium.io/en/v1.20/security/policy/troubleshooting/)
3. [v1.20 BGP control plane troubleshooting](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/)
4. [v1.20 BGP control plane operation](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/)
5. [v1.20 LB IPAM](https://docs.cilium.io/en/v1.20/network/lb-ipam/)
6. [v1.20 L2 announcements](https://docs.cilium.io/en/v1.20/network/l2-announcements/)
7. [v1.20 Gateway API troubleshooting](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/)
8. [Source: troubleshooting_servicemesh.rst](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_servicemesh.rst)
9. [v1.20 L7 traffic management](https://docs.cilium.io/en/v1.20/network/servicemesh/l7-traffic-management/)
10. [v1.20 Cluster Mesh setup](https://docs.cilium.io/en/v1.20/network/clustermesh/setup/)
11. [Source: troubleshooting_clustermesh.rst](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/troubleshooting_clustermesh.rst)
12. [v1.20 Hubble setup](https://docs.cilium.io/en/v1.20/observability/hubble/setup/)
13. [v1.20 Hubble TLS](https://docs.cilium.io/en/v1.20/observability/hubble/configuration/tls/)
14. [v1.20 Upgrade guide](https://docs.cilium.io/en/v1.20/operations/upgrade/)
15. [v1.20 Metrics reference](https://docs.cilium.io/en/v1.20/observability/metrics/)
16. [Source: upgrade-current.inc](https://raw.githubusercontent.com/cilium/cilium/main/Documentation/operations/upgrade-current.inc)
17. [Source: bugtool/cmd/configuration.go](https://github.com/cilium/cilium/blob/main/bugtool/cmd/configuration.go)
18. [Source: cilium-dbg/cmd/bgp_route_policy_get.go](https://github.com/cilium/cilium/blob/main/cilium-dbg/cmd/bgp_route_policy_get.go)
