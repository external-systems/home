# Cilium 1.20 Custom Resource Inventory

Research date: 2026-10-17. Primary source: Cilium `v1.20.0` tag in GitHub; docs from `docs.cilium.io/en/v1.20/`.

## Scope and method

- Version pinned to the Cilium `v1.20.0` source tag: registration in [`pkg/k8s/apis/cilium.io/client/register.go`](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/register.go), API packages [`v2/register.go`](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/register.go) and [`v2alpha1/register.go`](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2alpha1/register.go), and the generated CRD YAMLs under [`pkg/k8s/apis/cilium.io/client/crds/`](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/).
- CRD scope/version also cross-checked by parsing the embedded CRD YAMLs at `v1.20.0`.
- Lifecycle claims come from the rendered Cilium 1.20 docs or from `kubebuilder:deprecatedversion` / `deprecated: true` annotations in the CRD YAMLs.
- Post-1.20 additions are taken from the `main` branch (Cilium 1.21.0-dev) and explicitly noted as **not present in v1.20.0**.
- This inventory only covers CRDs owned by Cilium in the `cilium.io` API group. Upstream Kubernetes Gateway API CRDs and Kubernetes built-ins are listed separately.

## Summary

Cilium 1.20.0 ships **22 Cilium-owned CRDs**, all in API group `cilium.io`:

- 17 CRDs with `v2` as the storage/served version (7 of them also keep a deprecated `v2alpha1` version: the 5 BGP CRDs, CiliumCIDRGroup, and CiliumLoadBalancerIPPool).
- 5 CRDs that are `v2alpha1` only.

The canonical full CRD schemas are the generated YAML files committed in the repo; there is no separate docs-hosted schema reference page for every CRD.

## Exhaustive CRD table

| Kind | API Group / Version(s) | Scope | Short Names | Purpose | Audience | Lifecycle | Docs | Source | CRD YAML |
|------|------------------------|-------|-------------|---------|----------|-----------|------|--------|----------|
| CiliumBGPAdvertisement | cilium.io/v2, v2alpha1 (deprecated: v2alpha1) | Cluster | cbgpadvert | Defines prefixes and BGP attributes (PodCIDR, Service VIP, Interface IP, CiliumPodIPPool) injected into the BGP RIB. | User/admin (BGP control plane) | Stable v2; v2alpha1 deprecated | [docs](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-configuration/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/bgp_advert_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumbgpadvertisements.yaml) |
| CiliumBGPClusterConfig | cilium.io/v2, v2alpha1 (deprecated: v2alpha1) | Cluster | cbgpcluster | Defines BGP instances, node selectors, peers, and peer config references for the v2 BGP control plane. | User/admin (BGP control plane) | Stable v2; v2alpha1 deprecated | [docs](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-configuration/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/bgp_cluster_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumbgpclusterconfigs.yaml) |
| CiliumBGPNodeConfigOverride | cilium.io/v2, v2alpha1 (deprecated: v2alpha1) | Cluster | cbgpnodeoverride | Per-node overrides for router ID, local ASN, local port, and peering source address. | User/admin (BGP control plane) | Stable v2; v2alpha1 deprecated | [docs](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-configuration/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/bgp_node_override_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumbgpnodeconfigoverrides.yaml) |
| CiliumBGPNodeConfig | cilium.io/v2, v2alpha1 (deprecated: v2alpha1) | Cluster | cbgpnode | Operator-generated per-node derived BGP configuration; status reports reconcile state. | Internal/generated (read-only for users) | Stable v2; v2alpha1 deprecated | [docs](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-configuration/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/bgp_node_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumbgpnodeconfigs.yaml) |
| CiliumBGPPeerConfig | cilium.io/v2, v2alpha1 (deprecated: v2alpha1) | Cluster | cbgppeer | Reusable BGP session settings: timers, MD5 password, eBGP multihop, graceful restart, transport, AFI/SAFI. | User/admin (BGP control plane) | Stable v2; v2alpha1 deprecated | [docs](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-configuration/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/bgp_peer_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumbgppeerconfigs.yaml) |
| CiliumCIDRGroup | cilium.io/v2, v2alpha1 (deprecated: v2alpha1) | Cluster | ccg | Named group of external CIDRs referenced by CiliumNetworkPolicy via fromCIDRSet/cidrGroupRef. | User/admin (policy) | Stable v2; v2alpha1 deprecated | [docs](https://docs.cilium.io/en/v1.20/network/kubernetes/ciliumcidrgroup/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/cidrgroups_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumcidrgroups.yaml) |
| CiliumClusterwideEnvoyConfig | cilium.io/v2 | Cluster | ccec | Cluster-scoped raw Envoy xDS resources for Cilium's per-node Envoy; used by Ingress/Gateway API and advanced traffic management. | Cluster admin / implementation detail | Stable v2 | [docs](https://docs.cilium.io/en/v1.20/network/servicemesh/l7-traffic-management/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/ccec_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumclusterwideenvoyconfigs.yaml) |
| CiliumClusterwideNetworkPolicy | cilium.io/v2 | Cluster | ccnp | Cluster-scoped Cilium network policy with same spec as CiliumNetworkPolicy. | User/admin (policy) | Stable v2 | [docs](https://docs.cilium.io/en/v1.20/network/kubernetes/policy/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/ccnp_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumclusterwidenetworkpolicies.yaml) |
| CiliumDatapathPlugin | cilium.io/v2alpha1 (deprecated: v2alpha1) | Cluster | cddp | Registers an external datapath plugin and declares how Cilium should attach/reinitialize with it. | User/admin (datapath plugin registration) | Deprecated (v2alpha1 only; CRD marked deprecated) | _no dedicated docs page found_ | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2alpha1/cdpp_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2alpha1/ciliumdatapathplugins.yaml) |
| CiliumEgressGatewayPolicy | cilium.io/v2 | Cluster | cegp | Routes/SNATs egress traffic from selected pods to destination CIDRs through selected gateway node(s). | User/admin (egress gateway) | Stable v2 | [docs](https://docs.cilium.io/en/v1.20/network/egress-gateway/egress-gateway/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/cegp_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumegressgatewaypolicies.yaml) |
| CiliumEndpoint | cilium.io/v2 | Namespaced | cep, ciliumep | Per-pod status object created by the Cilium agent; mirrors endpoint identity, policy, networking, and state. | Internal/status (agent-generated) | Stable v2 | [docs](https://docs.cilium.io/en/v1.20/network/kubernetes/ciliumendpoint/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumendpoints.yaml) |
| CiliumEndpointSlice | cilium.io/v2alpha1 | Cluster | ces | Batches slim CiliumEndpoint objects to reduce apiserver load at scale. | Internal/operator-generated (enabled opt-in) | Beta (v2alpha1) | [docs](https://docs.cilium.io/en/v1.20/network/kubernetes/ciliumendpointslice/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2alpha1/types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2alpha1/ciliumendpointslices.yaml) |
| CiliumEnvoyConfig | cilium.io/v2 | Namespaced | cec | Namespaced raw Envoy xDS resources for Cilium's per-node Envoy. | Cluster admin / implementation detail | Stable v2 | [docs](https://docs.cilium.io/en/v1.20/network/servicemesh/l7-traffic-management/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/cec_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumenvoyconfigs.yaml) |
| CiliumGatewayClassConfig | cilium.io/v2alpha1 | Namespaced | cgcc | Cilium-specific GatewayClass parameters (service type, gRPC-web translation, server header transformation, etc.). | User/admin (Gateway API) | Alpha (v2alpha1) | [docs](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/parameterized-gatewayclass/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2alpha1/gatewayclassconfig_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2alpha1/ciliumgatewayclassconfigs.yaml) |
| CiliumIdentity | cilium.io/v2 | Cluster | ciliumid | Represents a Cilium security identity; backing store for identity allocation (CRD mode) or kvstore. | Internal (operator/agent generated); operator-managed identity mode is Beta | Stable v2 | [docs](https://docs.cilium.io/en/v1.20/network/kubernetes/identity-management-mode/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumidentities.yaml) |
| CiliumL2AnnouncementPolicy | cilium.io/v2alpha1 | Cluster | l2announcement | Controls which nodes announce which Service externalIPs/loadBalancerIPs on L2 via ARP/NDP. | User/admin (L2 Aware LB) | Beta (v2alpha1) | [docs](https://docs.cilium.io/en/v1.20/network/l2-announcements/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2alpha1/l2announcement_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2alpha1/ciliuml2announcementpolicies.yaml) |
| CiliumLoadBalancerIPPool | cilium.io/v2, v2alpha1 (deprecated: v2alpha1) | Cluster | ippools, ippool, lbippool, lbippools | Defines IP ranges from which Cilium LB IPAM allocates IPs for Services of type LoadBalancer. | User/admin (LB IPAM) | Stable v2; v2alpha1 deprecated | [docs](https://docs.cilium.io/en/v1.20/network/lb-ipam/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/lbipam_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumloadbalancerippools.yaml) |
| CiliumLocalRedirectPolicy | cilium.io/v2 | Namespaced | clrp | Redirects traffic matching a ClusterIP service or IP/port tuple to a node-local backend pod. | User/admin | Stable v2 | [docs](https://docs.cilium.io/en/v1.20/network/kubernetes/local-redirect-policy/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/clrp_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumlocalredirectpolicies.yaml) |
| CiliumNetworkPolicy | cilium.io/v2 | Namespaced | cnp, ciliumnp | Namespaced L3/L4/L7 network policy with Cilium-specific selectors and rules. | User/admin (policy) | Stable v2 | [docs](https://docs.cilium.io/en/v1.20/network/kubernetes/policy/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/cnp_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumnetworkpolicies.yaml) |
| CiliumNodeConfig | cilium.io/v2 | Namespaced | — | Applies per-node Cilium ConfigMap-style key/value overrides via label selector. | User/admin (node-level config) | Stable v2 (v2alpha1 removed in 1.20) | _no dedicated docs page found_ | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/cnc_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumnodeconfigs.yaml) |
| CiliumNode | cilium.io/v2 | Cluster | cn, ciliumn | Cilium's representation of a node; carries IPAM spec/status, cloud-provider metadata, encryption state. | Internal (agent/operator generated) | Stable v2 | _no dedicated docs page found_ | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumnodes.yaml) |
| CiliumPodIPPool | cilium.io/v2alpha1 | Cluster | cpip | Defines a pool of pod IPs for multi-pool IPAM mode. | User/admin (multi-pool IPAM) | v2alpha1 (feature documented as stable; API version still alpha) | [docs](https://docs.cilium.io/en/v1.20/network/kubernetes/ipam-multi-pool/) | [src](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2alpha1/ippool_types.go) | [crd](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2alpha1/ciliumpodippools.yaml) |

## Feature-to-CRD index

| Feature / area | Cilium-owned CRDs | Notes |
|----------------|-------------------|-------|
| BGP Control Plane (v2) | CiliumBGPClusterConfig, CiliumBGPPeerConfig, CiliumBGPAdvertisement, CiliumBGPNodeConfigOverride, CiliumBGPNodeConfig | All cluster-scoped; v2 is storage, v2alpha1 deprecated. |
| LoadBalancer IPAM | CiliumLoadBalancerIPPool | Cluster-scoped; v2 storage, v2alpha1 deprecated. |
| L2 Announcements / L2 Aware LB | CiliumL2AnnouncementPolicy | Beta; v2alpha1 only. Uses upstream `Lease` coordination objects. |
| Gateway API | CiliumGatewayClassConfig | Cilium-owned parameter CRD only. Gateway API route/Gateway CRDs are upstream `gateway.networking.k8s.io`. |
| Network policy | CiliumNetworkPolicy, CiliumClusterwideNetworkPolicy, CiliumCIDRGroup | CNP/CCNP stable v2; CCG stable v2 with deprecated v2alpha1. |
| Cilium Envoy Config | CiliumEnvoyConfig, CiliumClusterwideEnvoyConfig | Namespaced and cluster-scoped raw xDS resources; treated as cluster-admin/implementation-detail resources. |
| Egress Gateway | CiliumEgressGatewayPolicy | Stable v2. |
| Local Redirect Policy | CiliumLocalRedirectPolicy | Stable v2. |
| Multi-Pool IPAM | CiliumPodIPPool | v2alpha1 only; feature documented as stable. |
| Endpoint scalability | CiliumEndpoint, CiliumEndpointSlice | CEP is per-pod agent-generated; CES is operator-generated Beta batching mode. |
| Identity allocation | CiliumIdentity | Internal identity backing store; operator-managed mode is Beta. |
| Node representation / cloud IPAM | CiliumNode | Internal node object. |
| Node-level config overrides | CiliumNodeConfig | Stable v2; v2alpha1 removed in 1.20. |
| Datapath plugin registration | CiliumDatapathPlugin | Deprecated v2alpha1 only. |

## Not Cilium-owned: upstream Gateway API CRDs

Cilium's Gateway API controller consumes upstream CRDs from `gateway.networking.k8s.io`. In Cilium 1.20 these must be Gateway API **v1.6.1 or newer** (docs reference v1.6.3); see the [Gateway API support page](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/gateway-api/).

Required (Core conformance):
- `GatewayClass`, `Gateway`, `HTTPRoute`, `GRPCRoute`, `TLSRoute`, `BackendTLSPolicy`, `ReferenceGrant`

Optional:
- `ListenerSet`, `TCPRoute`, `UDPRoute`

Cilium only provides the `CiliumGatewayClassConfig` (`cilium.io/v2alpha1`) parameter CRD referenced from a `GatewayClass.parametersRef`.

## Kubernetes built-ins consumed by Cilium

These are not Cilium CRDs but are heavily consumed:
- `Node`, `Pod`, `Namespace`, `Service`, `Endpoints`, `EndpointSlice`
- `ConfigMap`, `Secret` (including TLS secrets for Gateway API/Ingress and BGP MD5 passwords)
- `ServiceAccount`, `Role`, `ClusterRole`, `RoleBinding`, `ClusterRoleBinding`
- `Lease` (used by L2 Announcements leader election)
- For MCS-API / Cluster Mesh: upstream `ServiceExport` and `ServiceImport` (not Cilium-owned)

## Version caveats and post-1.20 changes

1. **Removed `v2alpha1` for `CiliumNodeConfig`**: Cilium 1.20 removed the `v2alpha1` API version of `CiliumNodeConfig`; only `cilium.io/v2` remains. The v1.20 upgrade guide documents this breaking change ([upgrade guide](https://docs.cilium.io/en/v1.20/operations/upgrade/)).
2. **Deprecated `v2alpha1` versions on stable CRDs**: The following CRDs serve both `v2` (storage) and a deprecated `v2alpha1`: CiliumBGPClusterConfig, CiliumBGPPeerConfig, CiliumBGPAdvertisement, CiliumBGPNodeConfig, CiliumBGPNodeConfigOverride, CiliumCIDRGroup, CiliumLoadBalancerIPPool. Existing manifests using `cilium.io/v2alpha1` should migrate to `cilium.io/v2`.
3. **`CiliumDatapathPlugin` deprecated**: The entire CRD is marked `kubebuilder:deprecatedversion` and its only served version (`v2alpha1`) is flagged `deprecated: true` in the CRD YAML.
4. **`CiliumExternalWorkload` not present in 1.20**: This CRD existed in earlier Cilium releases but is **not registered in v1.20.0** (verified against `client/register.go` and `AllCiliumCRDResourceNames`). The feature appears to have been removed; the exact removal release was not confirmed in this pass.
5. **Post-1.20 additions (Cilium `main` / 1.21.0-dev)** — **not in v1.20.0**:
   - `CiliumNetworkDriverClusterConfig` (`ciliumnetworkdriverclusterconfigs.cilium.io/v2alpha1`, cluster-scoped) — source [`pkg/k8s/apis/cilium.io/v2alpha1/network_driver_types.go`](https://github.com/cilium/cilium/blob/main/pkg/k8s/apis/cilium.io/v2alpha1/network_driver_types.go), CRD [v2alpha1/ciliumnetworkdriverclusterconfigs.yaml](https://github.com/cilium/cilium/blob/main/pkg/k8s/apis/cilium.io/client/crds/v2alpha1/ciliumnetworkdriverclusterconfigs.yaml).
   - `CiliumNetworkDriverNodeConfig` (`ciliumnetworkdrivernodeconfigs.cilium.io/v2alpha1`, cluster-scoped) — same source file, CRD [v2alpha1/ciliumnetworkdrivernodeconfigs.yaml](https://github.com/cilium/cilium/blob/main/pkg/k8s/apis/cilium.io/client/crds/v2alpha1/ciliumnetworkdrivernodeconfigs.yaml).
   - `CiliumResourceIPPool` (`ciliumresourceippools.cilium.io/v2alpha1`, cluster-scoped) — source [`pkg/k8s/apis/cilium.io/v2alpha1/resource_ippool_types.go`](https://github.com/cilium/cilium/blob/main/pkg/k8s/apis/cilium.io/v2alpha1/resource_ippool_types.go), CRD [v2alpha1/ciliumresourceippools.yaml](https://github.com/cilium/cilium/blob/main/pkg/k8s/apis/cilium.io/client/crds/v2alpha1/ciliumresourceippools.yaml).
6. **CRD schema version**: The `v1.20.0` source labels CRDs with schema version `1.33.11` (`pkg/k8s/apis/cilium.io/register.go`). The rendered [CNP/CCNP compatibility table](https://docs.cilium.io/en/v1.20/network/kubernetes/compatibility-table/) lists `v1.20` at schema `1.33.10` and `latest/main` at `1.34.2`; the discrepancy between the branch table and the v1.20.0 tag constant was not reconciled.

## Canonical full CRD/schema reference

- Generated CRD YAMLs (canonical schemas): [`pkg/k8s/apis/cilium.io/client/crds/v2/`](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/) and [`v2alpha1/`](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2alpha1/). These are the same files embedded in the Cilium binary and applied by the operator.
- [`examples/crds`](https://github.com/cilium/cilium/blob/v1.20.0/examples/crds) is a symlink back to the above directory.
- Source type definitions: [`pkg/k8s/apis/cilium.io/v2/`](https://github.com/cilium/cilium/tree/v1.20.0/pkg/k8s/apis/cilium.io/v2) and [`v2alpha1/`](https://github.com/cilium/cilium/tree/v1.20.0/pkg/k8s/apis/cilium.io/v2alpha1).
- There is no single docs page hosting the full OpenAPI schema for all CRDs; per-CRD docs links are given in the table above.

## Uncertainties / not proven

- No dedicated rendered docs page was found for `CiliumNodeConfig`, `CiliumNode`, or `CiliumDatapathPlugin`; only source/type definitions and the upgrade guide (for `CiliumNodeConfig` removal) were located.
- The exact Cilium release in which `CiliumExternalWorkload` was removed has not been cross-checked against earlier release branches; only its absence in v1.20.0 is proven.
- Lifecycle labels for `CiliumPodIPPool` are ambiguous: the CRD version is `v2alpha1`, but the multi-pool IPAM feature docs do not include a beta warning and read as stable.
- The small mismatch between the v1.20.0 source CRD schema label (`1.33.11`) and the rendered v1.20 compatibility-table value (`1.33.10`) was not reconciled.
