# Cilium 1.20 Envoy config (CEC / CCEC)

Cilium Service Mesh exposes two CRDs that configure the Envoy component
built into Cilium agents:

- `CiliumEnvoyConfig` (`cilium.io/v2`, namespaced)
- `CiliumClusterwideEnvoyConfig` (`cilium.io/v2`, cluster-scoped)

Use cases include L7 traffic shifting, custom listeners, circuit
breaking, retries, and other advanced L7 traffic management.

## CRD fields

- `spec.resources` (required): list of Envoy xDS resources of types
  `Listener`, `RouteConfiguration`, `Cluster`, `ClusterLoadAssignment`,
  `Secret`.
- `spec.services`: Kubernetes Services whose traffic is redirected to an
  Envoy listener for L7 load-balancing.
- `spec.backendServices`: Kubernetes Services whose backends are synced
  to Envoy via EDS but whose traffic is **not** redirected to a
  listener.
- `spec.nodeSelector`: limits which agents apply the config (`nil` = all
  nodes).

Namespace behavior:

- For `CiliumEnvoyConfig`, Service namespace defaults to the CR's
  namespace.
- For `CiliumClusterwideEnvoyConfig`, Service namespace defaults to
  `default`.

## Required Helm/config flags

- L7 proxy must be enabled (`l7Proxy=true`, default).
- No separate Helm flag is required to enable the CRDs themselves.

## Important constraints

- **No Kubernetes validation**: Envoy resources are not validated by the
  API server. `kubectl apply` may succeed while the Cilium agent fails
  to parse/install the config. Check agent logs
  (`level=error|warning`).
- **Conflicts**: the agent logs warnings for conflicting Envoy
  resources; there is no automatic conflict resolution.
- **Ingress/Gateway API collision**: Cilium Ingress and Gateway API
  controllers generate `CiliumEnvoyConfig` resources under the hood.
  Manually created configs must not conflict with generated ones.
- **Agent availability**: when Envoy is embedded in the agent pod, L7
  traffic handled by these configs depends on the agent being
  available.
- East-west `CiliumEnvoyConfig` resources may require specific
  annotations to be intercepted; consult the L7 traffic-management docs
  for the exact annotation behavior in your use case.

## Failure detection

1. `kubectl apply` succeeds → does **not** mean Envoy accepted the
   config.
2. Check the agent logs for parse/install errors after applying.
3. Verify generated listeners/clusters with `cilium-dbg` or by
   inspecting the agent's Envoy admin interface as documented.

## Examples

- Traffic splitting:
  `examples/kubernetes/servicemesh/envoy/envoy-helloworld-v1-90-v2-10.yaml`
- Custom Prometheus listener:
  `examples/kubernetes/servicemesh/envoy/envoy-prometheus-metrics-listener.yaml`
- Circuit breaker:
  `examples/kubernetes/servicemesh/envoy/envoy-circuit-breaker.yaml`

## References

- [L7 traffic management](https://docs.cilium.io/en/v1.20/network/servicemesh/l7-traffic-management/)
- [Envoy traffic shifting](https://docs.cilium.io/en/v1.20/network/servicemesh/envoy-traffic-shifting/)
- [Envoy custom listener](https://docs.cilium.io/en/v1.20/network/servicemesh/envoy-custom-listener/)
- [Envoy circuit breaker](https://docs.cilium.io/en/v1.20/network/servicemesh/envoy-circuit-breaker/)
