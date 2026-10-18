# Cilium 1.20 network policy

## Resource types and scope

- Kubernetes `NetworkPolicy` — namespaced, standard K8s semantics.
- `CiliumNetworkPolicy` (`cilium.io/v2`, namespaced) — Cilium-specific
  L3/L4/L7 rules.
- `CiliumClusterwideNetworkPolicy` (`cilium.io/v2`, cluster-scoped) —
  same spec as CNP; also supports host policies via `nodeSelector`.

Direct import via the Cilium agent API/CLI is deprecated since v1.18
and removed in v1.19 — always use Kubernetes resources.

## Enforcement modes

Modes: `default`, `always`, `never`, configured via
`policyEnforcementMode` / `enable-policy`.

- `default` — endpoints are unrestricted until selected by a policy;
  then they switch to default-deny per direction.
- `always` — cluster-wide default-deny.
- `never` — policy enforcement disabled.

`spec.enableDefaultDeny` can disable default-deny for selected
endpoints, but **does not apply to L7 rules** — adding an L7 rule
without an allow-all still drops.

## Selectors

- `endpointSelector` selects pods; `nodeSelector` is allowed only in
  CCNP (host policies).
- Namespaced policies apply within their own namespace; cross-namespace
  matches require `k8s:io.kubernetes.pod.namespace` or namespace labels
  like `io.cilium.k8s.namespace.labels.<key>`.
- `matchExpressions` values within a single requirement are a logical
  AND; logical OR across keys requires separate `matchExpressions`
  blocks.
- Service accounts via `io.cilium.k8s.policy.serviceaccount`.
- In Cluster Mesh, `io.cilium.k8s.policy.cluster` selects the cluster.
- Node-based selectors require `nodeSelectorLabels: true`
  (`--enable-node-selector-labels`).

## Layer 3 policy

- Endpoint-based, service-based (`toServices`), entity-based,
  node-based, IP/CIDR-based, DNS/FQDN-based selectors.
- Entities: `host`, `remote-node`, `kube-apiserver`, `ingress`,
  `cluster`, `cluster-mesh`, `init`, `health`, `unmanaged`, `world`,
  `all`.
- `kube-apiserver` entity may not work for ingress traffic on AKS/GKE
  due to control-plane tunneling; egress restrictions generally work.

## CIDR groups (`CiliumCIDRGroup`)

- Cluster-scoped CRD (`cilium.io/v2`; `v2alpha1` deprecated) listing
  `spec.externalCIDRs`.
- Referenced from `fromCIDRSet` / `toCIDRSet` using the `cidrGroupRef`
  field.
- Reduces identity usage compared to many individual CIDRs.
- `cidrGroupSelector` is also available as an alternative reference
  mechanism.

Example:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-external-group
spec:
  endpointSelector: {}
  egress:
    - toCIDRSet:
        - cidrGroupRef:
            name: my-cidr-group
```

## DNS / FQDN policy

- `toFQDNs.matchName` and `matchPattern` allow connections to IPs
  returned in DNS responses.
- Patterns support `*` and `**.` wildcards with documented semantics.
- Requires L7 proxy enabled and a separate DNS policy rule (`toPorts` +
  `rules.dns`) to intercept DNS responses.
- `toFQDNs` rules cannot be combined with other L3 rules
  (`toEndpoints`, `toCIDR`).
- DNS TTLs are respected; IPs are cached per Cilium agent.
- Per-endpoint max IPs per hostname defaults to 50
  (`--tofqdns-endpoint-max-ip-per-hostname`).
- DNS policies do not support port ranges.
- The DNS proxy assumes intercepted responses come from trusted cluster
  DNS servers.

## Layer 4 policy

- `toPorts` with `port`, `endPort`, `protocol` (TCP/UDP/ANY).
- ICMP/ICMPv6 policy via `icmps` field with type integer or CamelCase
  message name.
- TLS SNI filtering via `serverNames` under `toPorts`.

## Layer 7 policy

- L7 rules are embedded in L4 `toPorts` rules; only one L7 rule type
  per port (HTTP or DNS).
- HTTP rules: regex matching on `path`, `method`, `host`, `headers`,
  `headerMatches`.
- DNS rules: `matchName` / `matchPattern`.
- Violations return application-level denials (HTTP 403, DNS REFUSED)
  rather than packet drops.
- L7 traffic is proxied through node-local Envoy; when Envoy is
  embedded in the agent pod, L7 traffic depends on agent availability.
- Host policies support only DNS L7 rules (beta).
- SNATed IPv6 pod-to-world L7 requires a kernel fix present in 6.14.1,
  6.12.22, 6.6.86, 6.1.133, 5.15.180, 5.10.236.

## Deny policies

- Deny policies take precedence over allow policies.
- Supported: `ingressDeny` / `egressDeny` at L3/L4.
- **Not supported**: L7 deny rules and `toFQDNs` deny rules.
- `--policy-deny-response=icmp` (experimental) returns ICMP unreachable
  for egress denials; ingress not supported.

## Default-deny practical note

When a pod is selected by an ingress rule, it can no longer receive
unlisted traffic. Add egress rules for reply dependent flows, DNS
especially — use `toFQDNs` with `matchName`/`matchPattern`.

## Deprecated / removed fields

- `fromRequires` / `toRequires` are deprecated as of Cilium 1.17.x and
  removed in 1.19.

## Diagnostics

```bash
# endpoints and identities
kubectl -n kube-system exec -ti <cilium-pod> -- cilium-dbg endpoint list
kubectl -n kube-system exec -ti <cilium-pod> -- cilium-dbg endpoint get <id>

# map endpoint to originating CNP/CCNP rules
kubectl -n kube-system exec -ti <cilium-pod> -- cilium-dbg endpoint get <id> \
  -o jsonpath='...derived-from-rules...' | tr -d '][' | \
  xargs -I{} cilium-dbg policy get {}

# FQDN cache and identity
cilium-dbg fqdn cache list
cilium-dbg ip list | grep <IP>
cilium-dbg policy selectors
cilium-dbg identity list
```

## References

- [Network policy overview](https://docs.cilium.io/en/v1.20/security/policy/)
- [Policy enforcement modes](https://docs.cilium.io/en/v1.20/security/policy/intro/)
- [Kubernetes constructs in policy](https://docs.cilium.io/en/v1.20/security/policy/kubernetes/)
- [Layer 3 policies](https://docs.cilium.io/en/v1.20/security/policy/layer3/)
- [Layer 4 policies](https://docs.cilium.io/en/v1.20/security/policy/layer4/)
- [Layer 7 policies](https://docs.cilium.io/en/v1.20/security/policy/layer7/)
- [Deny policies](https://docs.cilium.io/en/v1.20/security/policy/deny/)
- [Policy troubleshooting](https://docs.cilium.io/en/v1.20/security/policy/troubleshooting/)
- [CiliumCIDRGroup](https://docs.cilium.io/en/v1.20/network/kubernetes/ciliumcidrgroup/)
