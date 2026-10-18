# Cilium 1.20 Gateway API

Cilium implements the upstream Kubernetes Gateway API as an ingress /
service-mesh controller. Traffic is intercepted by eBPF and forwarded
to a per-node Envoy proxy via `TPROXY`.

## Supported upstream resources

Cilium 1.20 supports Gateway API **v1.6.3** and requires **v1.6.1
minimum**.

Required upstream CRDs (`gateway.networking.k8s.io`):

- `GatewayClass`
- `Gateway`
- `HTTPRoute`
- `GRPCRoute`
- `TLSRoute`
- `BackendTLSPolicy`
- `ReferenceGrant`

Optional upstream CRDs:

- `ListenerSet`
- `TCPRoute`
- `UDPRoute`

Cilium only supplies `CiliumGatewayClassConfig`
(`cilium.io/v2alpha1`) as a parameter CRD.

## Prerequisites

- `kubeProxyReplacement=true`
- `l7Proxy=true` (default)
- `gatewayAPI.enabled=true`; restart `deployment/cilium-operator` and
  `ds/cilium`
- `TPROXY`:
  - `bpf.tproxy=false` (default) uses iptables; nodes need the
    netfilter modules listed in the L7 proxy system requirements or
    Gateway connections time out.
  - `bpf.tproxy=true` (beta) removes the iptables dependency but is
    **incompatible with netkit datapath mode**.

## Cilium-specific GatewayClass parameters

`CiliumGatewayClassConfig` is referenced from
`GatewayClass.spec.parametersRef`. It is **alpha** and subject to
breaking changes.

Key fields:

- `service.type` — `LoadBalancer` or `NodePort`
- `service.externalTrafficPolicy`, `service.loadBalancerClass`,
  `service.ipFamilies`, `service.ipFamilyPolicy`,
  `service.allocateLoadBalancerNodePorts`,
  `service.loadBalancerSourceRanges`,
  `service.loadBalancerSourceRangesPolicy`,
  `service.trafficDistribution`
- `httpOptions.grpcWebTranslation.enabled` (default `true`)
- `envoy.serverHeaderTransformation`
- `telemetry.accessLogs` — JSON/Text, HTTP/TCP targets, Cilium-specific
  formatters

Example reference:
https://raw.githubusercontent.com/cilium/cilium/v1.20/examples/kubernetes/gateway/gateway-with-parameters.yaml

## Gateway addressing and host-network mode

- By default Cilium creates one LoadBalancer Service per Gateway.
- Host-network mode (`gatewayAPI.hostNetwork.enabled=true`) is mutually
  exclusive with LoadBalancer Service mode. Listener ports must be
  unique per Gateway; ports `<=1023` need `NET_BIND_SERVICE`
  capability.
- `spec.addresses` on `Gateway` is supported.
- `spec.infrastructure.annotations["io.cilium/lb-ipam-ips"]` currently
  takes precedence over `spec.addresses` but is planned for
  deprecation.
- Host-network mode is **not compatible** with `TCPRoute` and
  `UDPRoute`.

## Network policy and source-IP visibility

- Ingress/Gateway traffic is assigned the `ingress` identity. Policy
  must allow `world` → `ingress` and `ingress` → backend identities.
- Source IP visibility uses `X-Forwarded-For` /
  `X-Envoy-External-Address`. `externalTrafficPolicy: Local` is **not
  required** for Cilium Gateway API.
- TLS passthrough backends see the Envoy/node IP as the source.

## Version gates / 1.20 changes

- Gateway API v1.6.1 minimum because `TLSRoute` support moved to `v1`.
  Existing `TLSRoute` users must install the **experimental** TLSRoute
  CRD from Gateway API v1.6.1 (which still contains `v1alpha2`);
  installing the standard v1.6 TLSRoute CRD can cause existing objects
  to disappear from etcd.
- Annotations in the `cec.cilium.io/*` namespace supplied through
  Gateway/GAMMA infrastructure metadata are no longer propagated to
  internally generated `CiliumEnvoyConfig` resources.

## Failure modes

- Gateway stuck `Programmed=False` — check operator logs for missing
  Gateway API CRDs.
- `HTTPRoute` not attached — check parent conditions (`Accepted`,
  `ResolvedRefs`) for backend not found or invalid listener.
- No address — verify LB IPAM pool exists and matches the generated
  Service.
- 503 / no healthy upstream — check backend Service/Endpoints,
  generated `CiliumEnvoyConfig`, and Envoy EDS state.

## References

- [Gateway API support](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/gateway-api/)
- [Gateway API troubleshooting](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/troubleshooting/)
- [Parameterized GatewayClass](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/parameterized-gatewayclass/)
- [Upstream Gateway API overview](https://gateway-api.sigs.k8s.io/docs/concepts/api-overview/)
