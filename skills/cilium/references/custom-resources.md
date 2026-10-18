# Cilium 1.20 custom resources

Concise inventory of Cilium-owned CRDs in 1.20.0. For the full source
schemas see the generated CRD YAMLs and the `v2` / `v2alpha1` Go type
packages; this page only maps them to purpose and lifecycle.

Verified against the `v1.20.0` source tag. Post-1.20 additions are
labelled explicitly.

## At a glance

- **22 Cilium-owned CRDs** in API group `cilium.io`.
- **17** serve `cilium.io/v2` as the storage version (7 of those also
  keep a deprecated `v2alpha1` served version).
- **5** are `v2alpha1` only.

## CRD inventory

| Kind | API version(s) | Scope | Short names | Purpose | Audience | Lifecycle |
|---|---|---|---|---|---|---|
| `CiliumBGPAdvertisement` | `cilium.io/v2`, `v2alpha1` deprecated | Cluster | `cbgpadvert` | Prefixes and BGP attributes advertised by the v2 BGP control plane (PodCIDR, Service, Interface, CiliumPodIPPool). | User/admin | Stable v2; v2alpha1 deprecated |
| `CiliumBGPClusterConfig` | `cilium.io/v2`, `v2alpha1` deprecated | Cluster | `cbgpcluster` | BGP instances, `nodeSelector`, peers, and peer-config references. | User/admin | Stable v2; v2alpha1 deprecated |
| `CiliumBGPPeerConfig` | `cilium.io/v2`, `v2alpha1` deprecated | Cluster | `cbgppeer` | Reusable peer settings: timers, MD5 auth, multihop, graceful restart, transport, AFI/SAFI selectors. | User/admin | Stable v2; v2alpha1 deprecated |
| `CiliumBGPNodeConfigOverride` | `cilium.io/v2`, `v2alpha1` deprecated | Cluster | `cbgpnodeoverride` | Per-node overrides (router ID, local port/ASN/address). `metadata.name` must equal the node name. | User/admin | Stable v2; v2alpha1 deprecated |
| `CiliumBGPNodeConfig` | `cilium.io/v2`, `v2alpha1` deprecated | Cluster | `cbgpnode` | Operator-generated per-node derived BGP state. | Internal/generated | Stable v2; v2alpha1 deprecated |
| `CiliumCIDRGroup` | `cilium.io/v2`, `v2alpha1` deprecated | Cluster | `ccg` | Named set of external CIDRs referenced from `fromCIDRSet`/`toCIDRSet` via `cidrGroupRef`. | User/admin | Stable v2; v2alpha1 deprecated |
| `CiliumClusterwideEnvoyConfig` | `cilium.io/v2` | Cluster | `ccec` | Cluster-scoped raw Envoy xDS resources for Cilium's per-node Envoy. | Cluster admin / implementation detail | Stable v2 |
| `CiliumClusterwideNetworkPolicy` | `cilium.io/v2` | Cluster | `ccnp` | Cluster-scoped Cilium network policy; same spec as `CiliumNetworkPolicy`. | User/admin | Stable v2 |
| `CiliumDatapathPlugin` | `cilium.io/v2alpha1` | Cluster | `cddp` | Registers an external datapath plugin. | User/admin | Deprecated; v2alpha1 only |
| `CiliumEgressGatewayPolicy` | `cilium.io/v2` | Cluster | `cegp` | Egress SNAT/routing from selected pods to destination CIDRs through selected gateway nodes. | User/admin | Stable v2 |
| `CiliumEndpoint` | `cilium.io/v2` | Namespaced | `cep`, `ciliumep` | Per-pod status mirror (identity, policy, networking state). | Internal/status | Stable v2 |
| `CiliumEndpointSlice` | `cilium.io/v2alpha1` | Cluster | `ces` | Batched slim endpoint objects to reduce apiserver load. | Internal/operator-generated | Beta |
| `CiliumEnvoyConfig` | `cilium.io/v2` | Namespaced | `cec` | Namespaced raw Envoy xDS resources for Cilium's per-node Envoy. | Cluster admin / implementation detail | Stable v2 |
| `CiliumGatewayClassConfig` | `cilium.io/v2alpha1` | Namespaced | `cgcc` | Cilium-specific `GatewayClass` parameters (service type, gRPC-web, server header transformation, access logs). | User/admin | Alpha |
| `CiliumIdentity` | `cilium.io/v2` | Cluster | `ciliumid` | Cilium security identity backing store. | Internal | Stable v2; operator-managed identity mode is Beta |
| `CiliumL2AnnouncementPolicy` | `cilium.io/v2alpha1` | Cluster | `l2announcement` | Controls which nodes announce Service externalIPs/loadBalancerIPs via ARP/NDP. | User/admin | Beta |
| `CiliumLoadBalancerIPPool` | `cilium.io/v2`, `v2alpha1` deprecated | Cluster | `ippools`, `ippool`, `lbippool`, `lbippools` | IP ranges for LB IPAM allocation to `type: LoadBalancer` Services. | User/admin | Stable v2; v2alpha1 deprecated |
| `CiliumLocalRedirectPolicy` | `cilium.io/v2` | Namespaced | `clrp` | Redirects ClusterIP or IP/port traffic to a node-local backend. | User/admin | Stable v2 |
| `CiliumNetworkPolicy` | `cilium.io/v2` | Namespaced | `cnp`, `ciliumnp` | Namespaced L3/L4/L7 policy with Cilium selectors and rules. | User/admin | Stable v2 |
| `CiliumNodeConfig` | `cilium.io/v2` | Namespaced | — | Per-node ConfigMap-style key/value overrides via label selector. | User/admin | Stable v2; v2alpha1 removed in 1.20 |
| `CiliumNode` | `cilium.io/v2` | Cluster | `cn`, `ciliumn` | Cilium's node representation (IPAM, encryption, cloud metadata). | Internal | Stable v2 |
| `CiliumPodIPPool` | `cilium.io/v2alpha1` | Cluster | `cpip` | Pod IP pools for multi-pool IPAM mode. | User/admin | v2alpha1; feature documented as stable |

## Docs / source / schema links

| Kind | Docs | Source | CRD YAML |
|---|---|---|---|
| BGP CRDs | [BGP control plane configuration](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane-configuration/) | [`v2/bgp_*_types.go`](https://github.com/cilium/cilium/tree/v1.20.0/pkg/k8s/apis/cilium.io/v2) | [`client/crds/v2/ciliumbgp*.yaml`](https://github.com/cilium/cilium/tree/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2) |
| `CiliumCIDRGroup` | [docs](https://docs.cilium.io/en/v1.20/network/kubernetes/ciliumcidrgroup/) | [cidrgroups_types.go](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/cidrgroups_types.go) | [ciliumcidrgroups.yaml](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumcidrgroups.yaml) |
| `CiliumClusterwideEnvoyConfig` | [L7 traffic management](https://docs.cilium.io/en/v1.20/network/servicemesh/l7-traffic-management/) | [ccec_types.go](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/ccec_types.go) | [ciliumclusterwideenvoyconfigs.yaml](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumclusterwideenvoyconfigs.yaml) |
| `CiliumClusterwideNetworkPolicy` | [policy docs](https://docs.cilium.io/en/v1.20/network/kubernetes/policy/) | [ccnp_types.go](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/ccnp_types.go) | [ciliumclusterwidenetworkpolicies.yaml](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumclusterwidenetworkpolicies.yaml) |
| `CiliumEgressGatewayPolicy` | [egress gateway](https://docs.cilium.io/en/v1.20/network/egress-gateway/egress-gateway/) | [cegp_types.go](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/cegp_types.go) | [ciliumegressgatewaypolicies.yaml](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumegressgatewaypolicies.yaml) |
| `CiliumEndpoint` | [docs](https://docs.cilium.io/en/v1.20/network/kubernetes/ciliumendpoint/) | [types.go](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/types.go) | [ciliumendpoints.yaml](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumendpoints.yaml) |
| `CiliumEndpointSlice` | [docs](https://docs.cilium.io/en/v1.20/network/kubernetes/ciliumendpointslice/) | [v2alpha1/types.go](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2alpha1/types.go) | [v2alpha1/ciliumendpointslices.yaml](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2alpha1/ciliumendpointslices.yaml) |
| `CiliumEnvoyConfig` | [L7 traffic management](https://docs.cilium.io/en/v1.20/network/servicemesh/l7-traffic-management/) | [cec_types.go](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/cec_types.go) | [ciliumenvoyconfigs.yaml](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumenvoyconfigs.yaml) |
| `CiliumGatewayClassConfig` | [parameterized GatewayClass](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/parameterized-gatewayclass/) | [gatewayclassconfig_types.go](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2alpha1/gatewayclassconfig_types.go) | [v2alpha1/ciliumgatewayclassconfigs.yaml](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2alpha1/ciliumgatewayclassconfigs.yaml) |
| `CiliumIdentity` | [identity management](https://docs.cilium.io/en/v1.20/network/kubernetes/identity-management-mode/) | [types.go](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/types.go) | [ciliumidentities.yaml](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumidentities.yaml) |
| `CiliumL2AnnouncementPolicy` | [L2 announcements](https://docs.cilium.io/en/v1.20/network/l2-announcements/) | [l2announcement_types.go](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2alpha1/l2announcement_types.go) | [v2alpha1/ciliuml2announcementpolicies.yaml](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2alpha1/ciliuml2announcementpolicies.yaml) |
| `CiliumLoadBalancerIPPool` | [LB IPAM](https://docs.cilium.io/en/v1.20/network/lb-ipam/) | [lbipam_types.go](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/lbipam_types.go) | [ciliumloadbalancerippools.yaml](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumloadbalancerippools.yaml) |
| `CiliumLocalRedirectPolicy` | [local redirect policy](https://docs.cilium.io/en/v1.20/network/kubernetes/local-redirect-policy/) | [clrp_types.go](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/clrp_types.go) | [ciliumlocalredirectpolicies.yaml](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumlocalredirectpolicies.yaml) |
| `CiliumNetworkPolicy` | [policy docs](https://docs.cilium.io/en/v1.20/network/kubernetes/policy/) | [cnp_types.go](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/cnp_types.go) | [ciliumnetworkpolicies.yaml](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumnetworkpolicies.yaml) |
| `CiliumNodeConfig` | upgrade guide only | [cnc_types.go](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/cnc_types.go) | [ciliumnodeconfigs.yaml](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumnodeconfigs.yaml) |
| `CiliumNode` | no dedicated docs | [types.go](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2/types.go) | [ciliumnodes.yaml](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumnodes.yaml) |
| `CiliumPodIPPool` | [multi-pool IPAM](https://docs.cilium.io/en/v1.20/network/kubernetes/ipam-multi-pool/) | [ippool_types.go](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2alpha1/ippool_types.go) | [v2alpha1/ciliumpodippools.yaml](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2alpha1/ciliumpodippools.yaml) |
| `CiliumDatapathPlugin` | no dedicated docs | [cdpp_types.go](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/v2alpha1/cdpp_types.go) | [v2alpha1/ciliumdatapathplugins.yaml](https://github.com/cilium/cilium/blob/v1.20.0/pkg/k8s/apis/cilium.io/client/crds/v2alpha1/ciliumdatapathplugins.yaml) |

## Feature-to-CRD index

| Feature / area | CRDs |
|---|---|
| BGP Control Plane v2 | `CiliumBGPClusterConfig`, `CiliumBGPPeerConfig`, `CiliumBGPAdvertisement`, `CiliumBGPNodeConfigOverride`, `CiliumBGPNodeConfig` |
| LB IPAM | `CiliumLoadBalancerIPPool` |
| L2 Aware LB / L2 announcements | `CiliumL2AnnouncementPolicy` |
| Gateway API | `CiliumGatewayClassConfig` only (Gateway, HTTPRoute, etc. are upstream) |
| Network policy | `CiliumNetworkPolicy`, `CiliumClusterwideNetworkPolicy`, `CiliumCIDRGroup` |
| L7 / Service Mesh | `CiliumEnvoyConfig`, `CiliumClusterwideEnvoyConfig` |
| Egress Gateway | `CiliumEgressGatewayPolicy` |
| Local Redirect Policy | `CiliumLocalRedirectPolicy` |
| Multi-pool IPAM | `CiliumPodIPPool` |
| Endpoint scalability | `CiliumEndpoint`, `CiliumEndpointSlice` |
| Identity allocation | `CiliumIdentity` |
| Node config overrides | `CiliumNodeConfig` |
| Datapath plugin (deprecated) | `CiliumDatapathPlugin` |

## Upstream Gateway API CRDs (not Cilium-owned)

Cilium's Gateway API controller consumes upstream resources from
`gateway.networking.k8s.io`. Cilium 1.20 requires Gateway API **v1.6.1 or
newer**.

Required for core conformance:

- `GatewayClass`
- `Gateway`
- `HTTPRoute`
- `GRPCRoute`
- `TLSRoute`
- `BackendTLSPolicy`
- `ReferenceGrant`

Optional:

- `ListenerSet`
- `TCPRoute`
- `UDPRoute`

Cilium only supplies the `CiliumGatewayClassConfig` parameter CRD.

## Kubernetes built-ins heavily consumed

- Workloads / networking: `Node`, `Pod`, `Namespace`, `Service`,
  `Endpoints`, `EndpointSlice`
- Config / secrets: `ConfigMap`, `Secret` (TLS, BGP MD5 passwords)
- RBAC: `ServiceAccount`, `Role`, `ClusterRole`, `RoleBinding`,
  `ClusterRoleBinding`
- Coordination: `Lease` (L2 announcements leader election)
- Cluster Mesh MCS-API: `ServiceExport`, `ServiceImport`

## Version caveats and post-1.20 changes

1. **`CiliumNodeConfig` v2alpha1 removed in 1.20**. Only `cilium.io/v2`
   remains; migrate before upgrading.
2. **`v2alpha1` deprecated on stable CRDs**. The following still serve
   `v2alpha1` but it is deprecated: BGP CRDs, `CiliumCIDRGroup`,
   `CiliumLoadBalancerIPPool`. Prefer `cilium.io/v2`.
3. **`CiliumDatapathPlugin` deprecated**. Entire CRD is deprecated in
   1.20.
4. **`CiliumExternalWorkload` not present in 1.20**. Removed; not
   registered in `v1.20.0`.
5. **Post-1.20 additions on `main`** (not in v1.20.0):
   - `CiliumNetworkDriverClusterConfig`
   - `CiliumNetworkDriverNodeConfig`
   - `CiliumResourceIPPool`

## Open questions

- No dedicated rendered docs page was found for `CiliumNodeConfig`,
  `CiliumNode`, or `CiliumDatapathPlugin`.
- `CiliumPodIPPool` is `v2alpha1` even though the multi-pool IPAM feature
  reads as stable in the docs.
