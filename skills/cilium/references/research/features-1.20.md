# Cilium 1.20.x feature research (draft for skill update)

Scope: research notes for six feature branches in Cilium 1.20.x, intended to feed a major update of `skills/cilium/SKILL.md`.
Source policy: only primary sources — official Cilium versioned docs, official Cilium source/examples, and upstream Kubernetes Gateway API docs where specifically relevant.
Pinned claims use `/en/v1.20/` URLs; rolling/canonical links are marked `(rolling)`.
This file is **research**, not final skill prose.

---

## Canonical URL map

| ID | Topic | URL | Note |
|---|---|---|---|
| BGP1 | BGP Control Plane (v2) overview | https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane/ | pinned v1.20 |
| BGP2 | BGP Control Plane resources/configuration | https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-configuration/ | pinned v1.20 |
| BGP3 | BGP operation guide | https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-operation/ | pinned v1.20 |
| BGP4 | BGP troubleshooting | https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-troubleshooting/ | pinned v1.20 |
| BGP5 | `CiliumBGPClusterConfig` CRD | https://raw.githubusercontent.com/cilium/cilium/v1.20/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumbgpclusterconfigs.yaml | source v1.20 |
| LB1 | LB IPAM | https://docs.cilium.io/en/v1.20/network/lb-ipam/ | pinned v1.20 |
| LB2 | L2 Announcements | https://docs.cilium.io/en/v1.20/network/l2-announcements/ | pinned v1.20 |
| GW1 | Gateway API support | https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/gateway-api/ | pinned v1.20 |
| GW2 | GatewayClass parameters (`CiliumGatewayClassConfig`) | https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/parameterized-gatewayclass/ | pinned v1.20 |
| GW3 | Upstream Gateway API overview | https://gateway-api.sigs.k8s.io/docs/concepts/api-overview/ | upstream |
| GW4 | Upstream Gateway API home | https://gateway-api.sigs.k8s.io/ | upstream |
| CM1 | Cluster Mesh intro/architecture | https://docs.cilium.io/en/v1.20/network/clustermesh/intro/ | pinned v1.20 |
| CM2 | Setting up Cluster Mesh | https://docs.cilium.io/en/v1.20/network/clustermesh/setup/ | pinned v1.20 |
| CM3 | Load-balancing & Service Discovery | https://docs.cilium.io/en/v1.20/network/clustermesh/load-balancing/ | pinned v1.20 |
| CM4 | Global Services | https://docs.cilium.io/en/v1.20/network/clustermesh/global-services/ | pinned v1.20 |
| CM5 | Service Affinity | https://docs.cilium.io/en/v1.20/network/clustermesh/affinity/ | pinned v1.20 |
| CM6 | Multi-Cluster Services API (MCS-API) | https://docs.cilium.io/en/v1.20/network/clustermesh/mcsapi/ | pinned v1.20 |
| CM7 | Cluster Mesh network policy | https://docs.cilium.io/en/v1.20/network/clustermesh/policy/ | pinned v1.20 |
| POL1 | Network policy overview | https://docs.cilium.io/en/v1.20/security/policy/ | pinned v1.20 |
| POL2 | Policy enforcement modes | https://docs.cilium.io/en/v1.20/security/policy/intro/ | pinned v1.20 |
| POL3 | Kubernetes constructs in policy | https://docs.cilium.io/en/v1.20/security/policy/kubernetes/ | pinned v1.20 |
| POL4 | Layer 3 policies | https://docs.cilium.io/en/v1.20/security/policy/layer3/ | pinned v1.20 |
| POL5 | Layer 4 policies | https://docs.cilium.io/en/v1.20/security/policy/layer4/ | pinned v1.20 |
| POL6 | Layer 7 policies | https://docs.cilium.io/en/v1.20/security/policy/layer7/ | pinned v1.20 |
| POL7 | Deny policies | https://docs.cilium.io/en/v1.20/security/policy/deny/ | pinned v1.20 |
| POL8 | `CiliumNetworkPolicy` CRD | https://raw.githubusercontent.com/cilium/cilium/v1.20/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumnetworkpolicies.yaml | source v1.20 |
| POL9 | `CiliumCIDRGroup` CRD | https://raw.githubusercontent.com/cilium/cilium/v1.20/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumcidrgroups.yaml | source v1.20 |
| POL10 | `CiliumCIDRGroup` Go types | https://raw.githubusercontent.com/cilium/cilium/v1.20/pkg/k8s/apis/cilium.io/v2/cidrgroups_types.go | source v1.20 |
| ENV1 | L7 traffic shifting with `CiliumEnvoyConfig` | https://docs.cilium.io/en/v1.20/network/servicemesh/envoy-traffic-shifting/ | pinned v1.20 |
| ENV2 | L7 custom listener with `CiliumEnvoyConfig` | https://docs.cilium.io/en/v1.20/network/servicemesh/envoy-custom-listener/ | pinned v1.20 |
| ENV3 | L7 circuit breaking with `CiliumClusterwideEnvoyConfig` | https://docs.cilium.io/en/v1.20/network/servicemesh/envoy-circuit-breaker/ | pinned v1.20 |
| ENV4 | `CiliumEnvoyConfig` CRD | https://raw.githubusercontent.com/cilium/cilium/v1.20/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumenvoyconfigs.yaml | source v1.20 |
| ENV5 | `CiliumClusterwideEnvoyConfig` CRD | https://raw.githubusercontent.com/cilium/cilium/v1.20/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumclusterwideenvoyconfigs.yaml | source v1.20 |
| UP1 | Upgrade guide (1.20 notes) | https://docs.cilium.io/en/v1.20/operations/upgrade/ | pinned v1.20 |

---

## 1. BGP Control Plane (v2 CRD-based)

### Purpose and architecture
- The v2 BGP Control Plane advertises Pod and Service routes to external routers over BGP. It **does not program the datapath** and must not be used for in-cluster reachability [BGP1].
- The embedded speaker is GoBGP running inside each Cilium agent. The operator translates `CiliumBGPClusterConfig` into per-node `CiliumBGPNodeConfig` resources, which are the per-node source of truth [BGP1][BGP2].
- IPv4/IPv6 single-stack and dual-stack are supported, but the agent can only advertise address families it is configured with [BGP1].

### Required Helm/config flags
- Enable with Helm: `bgpControlPlane.enabled=true`, then restart `ds/cilium` [BGP1].
- To listen on port 179, grant `CAP_NET_BIND_SERVICE` via `securityContext.capabilities.ciliumAgent` [BGP2].
- Router ID allocation mode: `bgpControlPlane.routerIDAllocation.mode` (`default` or `ip-pool`) [BGP2].
- Secret namespace for MD5 passwords: `bgpControlPlane.secretNamespace.name` / `create` (default `kube-system`) [BGP2].

### Related CRDs and their role

| CRD | API | Scope | Role |
|---|---|---|---|
| `CiliumBGPClusterConfig` | `cilium.io/v2` (v2alpha1 deprecated) | Cluster | Defines BGP instances + peers; applied to nodes by `nodeSelector`. Max 16 BGP instances per config in the v2 CRD [BGP2][BGP5]. |
| `CiliumBGPPeerConfig` | `cilium.io/v2` | Namespaced? (docs show it as a namespaced-style resource, but it is referenced globally) | Shared peer settings: timers, auth, multihop, graceful restart, transport, address families [BGP2]. |
| `CiliumBGPAdvertisement` | `cilium.io/v2` | Namespaced | Defines prefixes to advertise and BGP path attributes (communities, local preference) [BGP2]. |
| `CiliumBGPNodeConfigOverride` | `cilium.io/v2` | Namespaced | Per-node overrides for router ID, local port, local ASN, local address. `metadata.name` must equal the node name; instance/peer names must match the `CiliumBGPClusterConfig` [BGP2]. |
| `CiliumBGPNodeConfig` | `cilium.io/v2` | Namespaced | Auto-generated by the operator; per-node live BGP state [BGP3]. |

### Version gates / deprecations
- `cilium.io/v2` is the current storage/served version for the BGP CRDs; `v2alpha1` is marked `deprecated: true` [BGP5].
- The old skill claims that any docs referencing kube-router or BIRD are deprecated legacy BGP mode. The v1.20 docs do **not** mention kube-router/BIRD; this claim could not be verified from the v1.20 pages and is listed as an open question below.
- In Cilium 1.20, listing BGP peers/routes/route-policies via the local REST API and `cilium-dbg bgp` is deprecated; the recommended path is `cilium shell -- bgp/*` [UP1].

### Important constraints and failure modes
- **No listener by default**: instances only initiate connections unless `localPort` is set [BGP2].
- **No BFD**: timers are the only fast-failure-detection knob. Minimum documented timers are `holdTimeSeconds=3`, `keepAliveTimeSeconds=1` [BGP2][BGP3].
- **Advertisement selector required**: peer-config `families[].advertisements` must match a `CiliumBGPAdvertisement` label; without a match no prefixes are advertised [BGP2].
- **MD5 auth caveats**: TCP MD5 signs the packet header, so NAT in the path breaks it (symptom: `dial: i/o timeout`). A missing Secret logs an error and the session proceeds with an empty password [BGP2].
- **ClusterConfig node selection must not overlap**: one `CiliumBGPClusterConfig` per node; operator rejects overlapping configs and sets `cilium.io/ConflictingClusterConfig` [BGP2][BGP4].
- **Service advertisements**: exact `/32` or `/128` by default; aggregation lengths are ignored when `externalTrafficPolicy: Local` (or `internalTrafficPolicy: Local` for ClusterIPs). `loadBalancerClass` must be unset or `io.cilium/bgp-control-plane` [BGP2].
- **Aggregation risks**: aggregated prefixes can blackhole/route-loop for unassigned VIPs (cilium#37623); overlapping aggregations with different attributes are undefined (cilium#40585) [BGP2].
- **Graceful restart**: recommended for agent upgrades; `restartTimeSeconds` (default 120) must exceed agent boot/image-pull time [BGP2][BGP3].
- **Operator dependency**: if the operator is down, new `CiliumBGPNodeConfig` provisioning, PodCIDR allocation, and LB-IPAM allocation stop [BGP3].
- **Service with no backends**: with `externalTrafficPolicy: Cluster`, the VIP stays advertised when `--enable-no-service-endpoints-routable=true` (default); with `Local`, advertisement stops [BGP3].

### Status conditions

| Resource | Condition | Meaning |
|---|---|---|
| `CiliumBGPClusterConfig` | `cilium.io/NoMatchingNode` | `nodeSelector` matches no nodes [BGP2][BGP4]. |
| `CiliumBGPClusterConfig` | `cilium.io/ConflictingClusterConfig` | Another ClusterConfig selects the same node [BGP2][BGP4]. |
| `CiliumBGPClusterConfig` | `cilium.io/MissingPeerConfigs` | A referenced `CiliumBGPPeerConfig` does not exist [BGP2][BGP4]. |
| `CiliumBGPPeerConfig` | `cilium.io/MissingAuthSecret` | Referenced Secret missing [BGP2][BGP3]. |

### Examples
- Containerlab examples live under `contrib/containerlab` in the Cilium repo [BGP2].
- Docs include full YAML for `CiliumBGPClusterConfig`, `CiliumBGPPeerConfig`, `CiliumBGPAdvertisement`, and `CiliumBGPNodeConfigOverride` [BGP2].

### Old-skill statement check
- “No listener by default” — **confirmed** [BGP2].
- “No BFD” — **confirmed** [BGP2][BGP3].
- “MD5 degrades silently to empty password when Secret missing” — **partially confirmed**: the agent logs an explicit error and continues with empty password [BGP2].
- “ClusterConfigs must not overlap node selection” — **confirmed** [BGP2][BGP4].
- “loadBalancerClass must be unset or `io.cilium/bgp-control-plane`” — **confirmed** [BGP2].
- “Upgrade with BGP: pre-pull image to avoid exceeding restartTimeSeconds” — **confirmed** [BGP3].

---

## 2. LB IPAM, L2 Announcements, and LoadBalancer Service behavior

### LB IPAM
- **Purpose**: assigns IP addresses to `type: LoadBalancer` Services in private-cloud / bare-metal environments. It does not advertise or load-balance; it pairs with BGP Control Plane or L2 Announcements [LB1].
- **Activation**: always enabled but dormant until the first `CiliumLoadBalancerIPPool` is created [LB1].
- **CRD**: `CiliumLoadBalancerIPPool` (`cilium.io/v2`) [LB1].
- **Pool blocks**: each item in `spec.blocks` is either a `cidr` or a single `start`+`stop` range [LB1].
- `spec.allowFirstLastIPs: No` reserves network/broadcast addresses for CIDR blocks; ignored for `/31`, `/32`, `/127`, `/128` [LB1].
- `spec.serviceSelector` limits which Services can use the pool [LB1].
- Overlapping CIDRs: the last-added pool is marked `Conflicting` (`cilium.io/PoolConflict`) and stops allocating [LB1].
- Updating a pool can reassign IPs and change Service VIPs (cilium#40358) [LB1].
- `disabled: true` drains a pool (no new allocations, existing kept) [LB1].
- Service annotations:
  - `lbipam.cilium.io/ips` — request specific IPs (comma-separated) [LB1].
  - `lbipam.cilium.io/sharing-key` — share VIPs across Services (ports must not conflict) [LB1].
  - `lbipam.cilium.io/sharing-cross-namespace` — allow cross-namespace sharing; must be present on **both** Services [LB1].
- Allocation failures surface as Service status condition `io.cilium/lb-ipam-request-satisfied` = `False` (e.g. reason `no_pool`) [LB1].
- Helm `defaultLBServiceIPAM=none` makes LB IPAM only allocate for Services with a recognized `loadBalancerClass` [LB1].

### LoadBalancer classes handled by Cilium
From the v1.20 LB IPAM page [LB1]:

| `loadBalancerClass` | Feature |
|---|---|
| (unset) | LB IPAM allocates |
| `io.cilium/bgp-control-plane` | Cilium BGP Control Plane |
| `io.cilium/l2-announcer` | L2 Announcements / L2 Aware LB (Beta) |

If the class is not handled by Cilium, LB IPAM ignores the Service and does **not** set a status condition [LB1].

### L2 Announcements (beta)
- **Purpose**: ARP/NDP-based alternative to BGP for flat networks without BGP routing [LB2].
- **Activation**: `l2announcements.enabled=true`, `kubeProxyReplacement=true`, plus `k8sClientRateLimit.qps/burst` sizing [LB2].
- **Prerequisites**: kube-proxy replacement; L2 devices must be included in the `devices` Helm option if explicitly set [LB2].
- **CRD**: `CiliumL2AnnouncementPolicy` (`cilium.io/v2alpha1`) [LB2].
- Policy fields: `serviceSelector`, `nodeSelector`, `interfaces` (regex), `externalIPs`, `loadBalancerIPs` [LB2].
- Service class must be unset or `io.cilium/l2-announcer` [LB2].
- **Incompatible with `externalTrafficPolicy: Local`** — may announce IPs on nodes without pods, causing drops [LB2].
- No load-balancing before traffic hits the cluster; one node answers ARP per IP. Leader election uses Kubernetes `Lease` objects in the Cilium namespace [LB2].
- Lease tuning Helm values: `l2announcements.leaseDuration` (default 15s), `leaseRenewDeadline` (5s), `leaseRetryPeriod` (2s); constraints documented [LB2].
- If using `externalIPs`, enable `externalIPs.enable=true` [LB2].
- Common failure: missing `coordination.k8s.io` `leases` RBAC when enabling manually without Helm [LB2].
- **L2 Pod Announcements** is a separate feature (`l2podAnnouncements.enabled=true`, `l2podAnnouncements.interfacePattern` regex); only ARP, no IPv6 yet [LB2].

### Old-skill statement check
- “LB IPAM always enabled, dormant until first pool” — **confirmed** [LB1].
- “Updating a pool can reassign IPs” — **confirmed** [LB1].
- “Sharing cross-namespace needs annotation on both services” — **confirmed** [LB1].
- “L2 announcements incompatible with `externalTrafficPolicy: Local`” — **confirmed** [LB2].
- “L2 announcements require kube-proxy replacement” — **confirmed** [LB2].

---

## 3. Gateway API support and Cilium-specific Gateway configuration

### Purpose and architecture
- Cilium implements the upstream Kubernetes Gateway API as an ingress/service-mesh controller. Traffic is intercepted by eBPF and transparently forwarded to a per-node Envoy proxy via `TPROXY` [GW1].
- Because Envoy is integrated with the eBPF policy engine, `CiliumNetworkPolicy` can be applied to ingress/Gateway traffic [GW1].

### Supported resources and versions
- Cilium 1.20 supports Gateway API **v1.6.3**. Core conformance tests pass [GW1].
- Supported resources: `GatewayClass`, `Gateway`, `HTTPRoute`, `GRPCRoute`, `TLSRoute`, `BackendTLSPolicy`, `ReferenceGrant`, `ListenerSet`, `TCPRoute`, `UDPRoute` [GW1].
- Required upstream CRDs (standard channel): GatewayClass, Gateway, HTTPRoute, GRPCRoute, BackendTLSPolicy, ReferenceGrant, TLSRoute [GW1].
- Optional upstream CRDs: ListenerSet, TCPRoute, UDPRoute [GW1].

### Prerequisites / Helm flags
- `kubeProxyReplacement=true` [GW1].
- `l7Proxy=true` (default) [GW1].
- `gatewayAPI.enabled=true`; restart `deployment/cilium-operator` and `ds/cilium` [GW1].
- `TPROXY`: default `bpf.tproxy=false` uses iptables; nodes must have the netfilter modules listed in the L7 proxy system requirements or Gateway connections time out. `bpf.tproxy=true` (beta) removes the iptables dependency [GW1].
- `bpf.tproxy=true` is **incompatible with netkit datapath mode** [UP1].

### Cilium-specific Gateway configuration resource
- `CiliumGatewayClassConfig` (`cilium.io/v2alpha1`) is referenced by `GatewayClass.spec.parametersRef` [GW2].
- It is an **alpha API** and subject to breaking changes [GW2].
- Supported fields include:
  - `service.type` (`LoadBalancer` or `NodePort`)
  - `service.externalTrafficPolicy`, `service.loadBalancerClass`, `service.ipFamilies`, `service.ipFamilyPolicy`, `service.allocateLoadBalancerNodePorts`, `service.loadBalancerSourceRanges`, `service.loadBalancerSourceRangesPolicy`, `service.trafficDistribution`
  - `httpOptions.grpcWebTranslation.enabled` (default `true`)
  - `envoy.serverHeaderTransformation`
  - `telemetry.accessLogs` (JSON/Text, HTTP/TCP targets, Cilium-specific formatters) [GW2].

### Gateway addressing and host-network mode
- By default Cilium creates a LoadBalancer Service per Gateway [GW1].
- Host-network mode (since Cilium 1.16): `gatewayAPI.hostNetwork.enabled=true`. Mutually exclusive with LoadBalancer Service mode; listener port unique per Gateway; ports `<=1023` require `NET_BIND_SERVICE` capability [GW1].
- `spec.addresses` on `Gateway` is supported. `spec.infrastructure.annotations["io.cilium/lb-ipam-ips"]` currently takes precedence but is planned for deprecation [GW1].
- Host-network mode is **not compatible** with `TCPRoute` and `UDPRoute` [GW1].

### Network policy and source-IP visibility
- Ingress/Gateway traffic is assigned the `ingress` identity. Policy must allow `world` → `ingress` and `ingress` → backend identities [GW1].
- Source IP visibility works via `X-Forwarded-For` / `X-Envoy-External-Address`; `externalTrafficPolicy: Local` is **not required** for Cilium Gateway API [GW1].
- TLS passthrough backends see the Envoy/node IP as the source [GW1].

### Version gates / 1.20 changes
- Cilium 1.20 requires Gateway API **v1.6.1 minimum** because `TLSRoute` support moved to `v1`. Existing `TLSRoute` users **must** install the **experimental** TLSRoute CRD from Gateway API v1.6.1 (which still contains `v1alpha2`); installing the standard v1.6 TLSRoute CRD can cause existing objects to disappear from etcd [UP1].
- Annotations in the `cec.cilium.io/*` namespace supplied through Gateway/GAMMA infrastructure metadata are no longer propagated to internally generated `CiliumEnvoyConfig` resources [UP1].

### Examples
- HTTP, HTTPS, gRPC, traffic splitting, header modification, GatewayClass parameters, default TLS certificate, BackendTLSPolicy, access logs, ListenerSet examples are linked from the Gateway API support page [GW1].
- Example YAML: https://raw.githubusercontent.com/cilium/cilium/v1.20/examples/kubernetes/gateway/gateway-with-parameters.yaml [GW2].

### Old-skill statement check
- The old skill was largely silent on Gateway API; the notes above are new primary-source material.

---

## 4. Cluster Mesh setup, configuration, and requirements

### Purpose and architecture
- Cluster Mesh extends Cilium networking across multiple Kubernetes clusters, providing pod-to-pod connectivity, cluster-aware policy enforcement, cross-cluster service discovery/load-balancing, and service affinity [CM1].
- Per-cluster control plane runs as `clustermesh-apiserver` pods containing: `etcd` (embedded, no persistent storage), `apiserver` (syncs local state), and `kvstoremesh` (syncs remote state) [CM1].
- Pod-to-pod traffic is forwarded directly between nodes; no extra proxy/gateway [CM1].
- In kvstore mode, Cluster Mesh extends the existing etcd instead of deploying a new one [CM1].

### Security model
- All connected clusters form a single trust domain. Cilium sanity-checks remote state but cannot fully prevent a compromised cluster from propagating malicious information [CM1].

### Requirements
- Same datapath mode in all clusters [CM2].
- Cilium versions may differ by **no more than one minor release** [CM2].
- Unique, non-conflicting PodCIDR ranges across all clusters/nodes [CM2].
- Node InternalIP connectivity between clusters (peering/VPN) [CM2].
- Firewall rules must allow inter-cluster traffic on the documented ports [CM2].
- Native-routed mode: `ipv4NativeRoutingCIDR` must cover all PodCIDRs; pods must have IP connectivity across clusters [CM2].
- `maxConnectedClusters`: default `255` (max local identities 65535); can be `511` (max local identities 32767). Must be the same in all clusters and set at install time; changing it live can disrupt connectivity/policy enforcement [CM2].
- Unique cluster name (≤32 chars, lowercase alnum/dash) and numeric cluster ID (1–255). Changing either requires restarting all workloads [CM2].

### TLS configuration
- Control-plane connections use mTLS. Auto options: certgen CronJob, cert-manager, or Helm. Every cluster must trust the others; use a common CA or `tls.caBundle` [CM2].
- Certgen default validity is 1 year; cronJob mode regenerates every 4 months in Cilium 1.20 [UP1].
- Helm-generated certs are only renewed when the chart is re-rendered (typically during upgrade); upgrade at least annually or set a longer `certValidityDuration` [UP1].
- In Cilium 1.20, `clustermesh.apiserver.tls.server.{extraDnsNames,extraIpAddresses}` are replaced by `clustermesh.apiserver.tls.auto.server.{extraDnsNames,extraIpAddresses}` (old values still fall back) [UP1].
- `clustermesh-apiserver.cilium.io` DNS name is no longer included by default [UP1].

### Service discovery / load-balancing options
- **Global Services**: identical Service name/namespace in each cluster + annotation `service.cilium.io/global: "true"`. `service.cilium.io/shared: "true"` is the default; `shared: "false"` exports remote backends without sharing local ones [CM4].
- **Service affinity**: `service.cilium.io/affinity: "none|local|remote"` [CM5].
- **EndpointSlice synchronization** (beta): `clustermesh.enableEndpointSliceSynchronization=true`; default off for non-headless Global Services, default on for headless. Needed for some third-party controllers/ingress controllers that read EndpointSlices [CM4].
- **MCS-API**: Kubernetes SIG-Multicluster standard using `ServiceExport`/`ServiceImport`. Enable with `clustermesh.mcsapi.enabled=true`; CoreDNS 1.12.2+ required; Cilium can auto-configure CoreDNS with `clustermesh.mcsapi.corednsAutoConfigure.enabled=true` [CM6].
- `clustermesh.cacheTTL` (default `0s`) revokes cached remote-cluster data after a duration of unreachable-ness; `0s` means never revoke [CM4].

### Network policy across clusters
- Policy enforcement automatically spans clusters, but K8s policies are **not** automatically distributed; apply `CiliumNetworkPolicy` / `NetworkPolicy` in every cluster [CM7].
- Use label `io.cilium.k8s.policy.cluster` to target specific clusters [CM7].
- `policy-default-local-cluster` (introduced 1.18, default in 1.19) restricts endpoint selection to the local cluster by default; set `clustermesh.policyDefaultLocalCluster` to migrate [UP1].

### Limitations
- Global NodePort Services load-balance across local+remote backends only with `kubeProxyReplacement=true` [CM4].
- Node/host-network access to global services needs SocketLB host-namespace support (`socketLB.enabled=true`, `socketLB.hostNamespaceOnly=true`) otherwise only local backends are used [CM4].

### Old-skill statement check
- The old skill did not cover Cluster Mesh; all material above is new.

---

## 5. Network policy: K8s NP, CNP, CCNP, CIDR groups, DNS/FQDN, deny, and L7

### Resource types and scope
- Cilium supports Kubernetes `NetworkPolicy`, `CiliumNetworkPolicy` (namespaced), and `CiliumClusterwideNetworkPolicy` (cluster-scoped) [POL1][POL3].
- Direct import via the Cilium agent API/CLI is deprecated since v1.18 and removed in v1.19 [POL1].

### Enforcement modes and default-deny
- Modes: `default`, `always`, `never`, configured via `policyEnforcementMode` / `enable-policy` [POL2].
- In `default` mode, endpoints are unrestricted until selected by a policy; then they switch to default-deny per direction [POL2].
- `spec.enableDefaultDeny` can disable default-deny for selected endpoints, but **it does not apply to L7 rules** — adding an L7 rule without an allow-all still drops [POL2].

### Selectors and Kubernetes constructs
- `endpointSelector` selects pods; `nodeSelector` is allowed only in `CiliumClusterwideNetworkPolicy` (host policies) [POL2][POL3].
- Namespaced policies apply within their own namespace; cross-namespace matches require `k8s:io.kubernetes.pod.namespace` or namespace labels like `io.cilium.k8s.namespace.labels.<key>` [POL3].
- `matchExpressions` values within a single requirement are a logical AND; logical OR across keys requires separate `matchExpressions` blocks [POL3].
- Service accounts can be matched via `io.cilium.k8s.policy.serviceaccount` [POL3].
- In Cluster Mesh, `io.cilium.k8s.policy.cluster` selects the cluster [POL3][CM7].
- Node-based selectors require `nodeSelectorLabels: true` (`--enable-node-selector-labels`) [POL4].

### Layer 3 policy
- Endpoint-based, service-based (`toServices`), entity-based, node-based, IP/CIDR-based, and DNS/FQDN-based selectors [POL4].
- Entities: `host`, `remote-node`, `kube-apiserver`, `ingress`, `cluster`, `cluster-mesh`, `init`, `health`, `unmanaged`, `world`, `all` [POL4].
- `kube-apiserver` entity may not work for ingress traffic on AKS/GKE due to control-plane tunneling; egress restrictions generally work [POL4].

### CIDR groups (`CiliumCIDRGroup`)
- `CiliumCIDRGroup` is a cluster-scoped CRD (`cilium.io/v2`; `v2alpha1` deprecated) that lists `spec.externalCIDRs` and is referenced from `fromCIDRSet` / `toCIDRSet` using `cidrGroupRef` [POL9][POL10].
- The CRD description explicitly states it is for **external CIDRs** (peers outside the clusters) [POL9].
- It reduces identity usage compared to many individual CIDRs [POL4].
- `cidrGroupSelector` is also available as an alternative reference mechanism [POL8].
- **Old-skill correction**: the old skill says policies reference CIDR groups by `io.cilium.CIDRGroupName`. The actual YAML field is `cidrGroupRef` inside a `fromCIDRSet`/`toCIDRSet` entry; the internal label generated is `io.cilium.policy.cidrgroupname/<name>` [POL8][POL10]. The old shorthand is imprecise.

### DNS / FQDN policy
- `toFQDNs.matchName` and `matchPattern` allow connections to IPs returned in DNS responses. Patterns support `*` and `**.` wildcards with documented semantics [POL4][POL6].
- Requires L7 proxy enabled and a separate DNS policy rule (`toPorts` + `rules.dns`) to intercept DNS responses [POL4][POL6].
- `toFQDNs` rules cannot be combined with other L3 rules (`toEndpoints`, `toCIDR`) [POL4].
- DNS TTLs are respected; IPs are cached per Cilium agent [POL6].
- Per-endpoint max IPs per hostname defaults to 50 (`--tofqdns-endpoint-max-ip-per-hostname`) [POL4].
- DNS policies do not support port ranges [POL6].
- The DNS proxy assumes intercepted responses come from trusted cluster DNS servers (threat-model note) [POL6].

### Layer 4 policy
- `toPorts` with `port`, `endPort`, `protocol` (TCP/UDP/ANY) [POL5].
- ICMP/ICMPv6 policy via `icmps` field with type integer or CamelCase message name [POL5].
- TLS SNI filtering via `serverNames` under `toPorts` [POL5].

### Layer 7 policy
- L7 rules are embedded in L4 `toPorts` rules; only one L7 rule type per port (HTTP or DNS) [POL6].
- HTTP rules: regex matching on `path`, `method`, `host`, `headers`, `headerMatches` [POL6].
- DNS rules: `matchName` / `matchPattern` [POL6].
- Violations return application-level denials (HTTP 403, DNS REFUSED) rather than packet drops [POL6].
- L7 traffic is proxied through node-local Envoy; when Envoy is embedded in the agent pod, L7 traffic depends on agent availability [POL6].
- Host policies support only DNS L7 rules (beta) [POL6].
- SNATed IPv6 pod-to-world L7 requires a kernel fix present in 6.14.1, 6.12.22, 6.6.86, 6.1.133, 5.15.180, 5.10.236 [POL6].

### Deny policies
- Deny policies take precedence over allow policies [POL7].
- Supported: `ingressDeny` / `egressDeny` at L3/L4.
- **Not supported**: L7 deny rules and `toFQDNs` deny rules [POL7].
- `--policy-deny-response=icmp` (experimental) returns ICMP unreachable for egress denials; ingress not supported [POL2].

### Deprecated / removed policy fields
- `fromRequires` / `toRequires` are deprecated as of Cilium 1.17.x and removed in 1.19 [POL4].

### Old-skill statement check
- “Agent-API import path deprecated since 1.18, removed in 1.19” — **confirmed** [POL1].
- “Deny rules override allows” — **confirmed** [POL7].
- “Empty/absent rules = allow all unless enforcement mode set” — **confirmed with nuance**: default-deny is triggered when a policy selects the endpoint and contains the relevant direction [POL2].
- “CiliumCIDRGroup referenced by `io.cilium.CIDRGroupName`” — **incorrect/imprecise**; actual field is `cidrGroupRef` [POL8][POL10].

---

## 6. `CiliumEnvoyConfig` and `CiliumClusterwideEnvoyConfig`

### Purpose and architecture
- Cilium Service Mesh exposes two CRDs that let users configure the Envoy component built into Cilium agents: `CiliumEnvoyConfig` (namespaced) and `CiliumClusterwideEnvoyConfig` (cluster-scoped) [ENV1][ENV2][ENV3].
- Use cases include L7 traffic shifting, custom listeners, circuit breaking, retries, etc. [ENV1][ENV2][ENV3].

### CRDs and fields
- Both CRDs are `cilium.io/v2` [ENV4][ENV5].
- `spec.resources` (required): list of Envoy xDS resources of types `Listener`, `RouteConfiguration`, `Cluster`, `ClusterLoadAssignment`, `Secret` [ENV4][ENV5].
- `spec.services`: Kubernetes Services whose traffic is redirected to an Envoy listener for L7 load-balancing [ENV4][ENV5].
- `spec.backendServices`: Kubernetes Services whose backends are synced to Envoy via EDS but whose traffic is **not** redirected to a listener [ENV4][ENV5].
- `spec.nodeSelector`: limits which agents apply the config (nil = all nodes) [ENV4][ENV5].
- Namespace behavior: for `CiliumEnvoyConfig`, Service namespace defaults to the CR’s namespace; for `CiliumClusterwideEnvoyConfig`, it defaults to `default` [ENV4][ENV5].

### Required Helm/config flags
- L7 proxy must be enabled (`l7Proxy=true`, default) [GW1][POL6].
- No separate Helm flag is required to enable the CRDs themselves; they are part of Cilium Service Mesh.

### Important constraints and failure modes
- **No Kubernetes validation**: Envoy resources are not validated by the API server. `kubectl apply` may succeed while the Cilium agent fails to parse/install the config. Check agent logs (`level=error|warning`) [ENV1][ENV2][ENV3].
- **Conflicts**: the agent logs warnings for conflicting Envoy resources [ENV1][ENV2][ENV3].
- **Ingress controller collision**: Cilium Ingress/Gateway API controllers generate `CiliumEnvoyConfig` resources under the hood; manually created configs must not conflict with them [ENV1][ENV2][ENV3].
- **Agent availability**: when Envoy is embedded in the agent pod, L7 traffic handled by these configs depends on the agent being available [POL6].

### Examples
- Traffic splitting: `examples/kubernetes/servicemesh/envoy/envoy-helloworld-v1-90-v2-10.yaml` [ENV1].
- Custom Prometheus listener: `examples/kubernetes/servicemesh/envoy/envoy-prometheus-metrics-listener.yaml` [ENV2].
- Circuit breaker: `examples/kubernetes/servicemesh/envoy/envoy-circuit-breaker.yaml` [ENV3].

### Old-skill statement check
- The old skill did not cover `CiliumEnvoyConfig`; all material above is new.

---

## Verified 1.20+ changes (from the 1.20 upgrade guide)

- Gateway API now requires v1.6.1 minimum because `TLSRoute` moved to `v1`; existing `TLSRoute` users must install the **experimental** TLSRoute CRD from v1.6.1 [UP1].
- `cec.cilium.io/*` infrastructure annotations are no longer propagated to internally generated `CiliumEnvoyConfig` resources [UP1].
- BGP peers/routes/route-policies via the local REST API and `cilium-dbg bgp` are deprecated; use `cilium shell -- bgp/*` [UP1].
- Cluster Mesh automatic certificate default validity reduced to 1 year; cronJob mode regenerates every 4 months; Helm method only renews on chart re-render [UP1].
- `clustermesh.apiserver.tls.server.{extraDnsNames,extraIpAddresses}` replaced by `clustermesh.apiserver.tls.auto.server.*` (fallback preserved) [UP1].
- `clustermesh-apiserver.cilium.io` DNS name no longer included by default [UP1].
- `clustermesh.enableMCSAPISupport` removed in favor of `clustermesh.mcsapi.enabled` [UP1].
- `bpf.tproxy=true` incompatible with netkit datapath mode [UP1].
- CNI config defaults to standard v1.0.0 [UP1].

---

## Open questions / not verified from v1.20 primary sources

1. **Legacy BGP mode (kube-router/BIRD)**: the old skill states that docs referencing kube-router or BIRD describe a deprecated legacy BGP mode. The v1.20 BGP docs do not mention these, so this statement could not be directly verified; it may be historically accurate but is not reflected in current primary docs.
2. **BFD support timeline**: v1.20 docs still state BFD is not supported. No official timeline for BFD has been found.
3. **Exact Helm default for `defaultLBServiceIPAM`**: the docs show the value `none` to opt out of allocating for unclassified Services, but do not explicitly state the default value (`nil`/unset behavior) in the Helm reference excerpt we retrieved.
4. **CiliumGatewayClassConfig future stability**: marked alpha and subject to breaking changes; specific 1.20→1.21 deprecations are not documented in the retrieved pages.
5. **CiliumEnvoyConfig admission/validation**: no admission webhook or server-side validation is documented; error detection relies entirely on agent logs.

---

## How to use this file

- Each branch is self-contained with citations by URL-map ID.
- Claims that are unverified or corrected from the old skill are flagged explicitly.
- Before writing final skill prose, resolve the open questions and cross-check against the current cluster’s running Cilium version.
