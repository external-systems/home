# k3d Operational Reference

Reference for running lightweight k3s clusters in Docker with k3d, replacing the default CNI with Cilium >= 1.20, and exposing Traefik on host ports 80/443 through k3d's load balancer plus Cilium Node IPAM. Rancher Manager, generic Kubernetes depth, Flannel details, and k3s ServiceLB are out of scope. Traefik is covered only as the ingress/Gateway implementation for this local lab.

---

## Version assumptions

Docker >= 20.10.5, `kubectl`, k3d v5.9.0+ ([cluster create docs](https://k3d.io/v5.9.0/usage/commands/k3d_cluster_create/)), k3s v1.32+, Cilium 1.20.x, and Helm v3. ([k3d.io](https://k3d.io/))

---

## What k3d is

k3d is a community-driven wrapper that runs [k3s](https://k3s.io/) inside Docker. It is useful for local development and CI but is **not** an official Rancher/SUSE product. ([k3d.io](https://k3d.io/)) A cluster contains one or more `server` containers, zero or more `agent` containers, and an optional `serverlb` (`k3d-proxy`) container in front of the servers.

---

## Install k3d

```bash
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
# or pin a tag
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.9.0 bash
```

Also available via `brew install k3d`, `choco install k3d`, or `go install github.com/k3d-io/k3d/v5@latest`.

---

## Basic lifecycle and CLI

```bash
# create clusters
k3d cluster create mycluster
k3d cluster create mycluster --servers 1 --agents 2 --api-port 6443 --wait

# lifecycle
k3d cluster stop mycluster
k3d cluster start mycluster
k3d cluster delete mycluster
k3d cluster delete -a

# list clusters and nodes
k3d cluster list
k3d node list mycluster
```

Reference: [k3d v5.9.0 command tree](https://k3d.io/v5.9.0/usage/commands/k3d_cluster_create/)

### kubeconfig

`k3d cluster create` merges the kubeconfig and switches context by default. Manual options:

```bash
export KUBECONFIG=$(k3d kubeconfig write mycluster)
k3d kubeconfig merge mycluster --kubeconfig-switch-context
```

### Node filters

Many flags accept `@<group>:<subset>` filters:

- groups: `server`, `servers`, `agent`, `agents`, `loadbalancer`, `all`
- subset: index (`0`), list (`1,2`), range (`0-2`), or wildcard `*`

Example: `--k3s-arg "--disable=traefik@server:0"` applies only to the first server. ([nodefilter docs](https://k3d.io/v5.8.3/design/concepts/))

### Agents

```bash
# at create time
k3d cluster create mycluster --agents 2

# later
k3d node create mycluster-agent-2 --cluster mycluster --role agent
```

In k3d, agents are worker-only containers; servers also run an embedded agent by default.

---

## Registries and images

### k3d-managed registries

```bash
# create a registry with the cluster
k3d cluster create mycluster --registry-create mycluster-registry

# use an existing registry
k3d registry create myregistry.localhost --port 5000
k3d cluster create mycluster --registry-use k3d-myregistry.localhost:5000
```

k3d writes a k3s `registries.yaml` so cluster nodes can resolve and pull from the registry. ([k3d registries docs](https://k3d.io/v5.9.0/usage/registries/))

### Import local images

```bash
k3d image import myimage:tag -c mycluster
```

---

## Port publishing and the k3d load balancer

k3d creates a `serverlb` container in front of the servers. Port mappings using `@loadbalancer` go through it:

```bash
k3d cluster create mycluster -p "8080:80@loadbalancer"
```

Mechanics and limits:

- The `serverlb` proxies a port to **all** server nodes on the same container port. ([k3d exposing services](https://k3d.io/v5.9.0/usage/exposing_services/))
- To target a specific agent, use `@agent:0`, `@agent:1`, etc.
- Mapping the full NodePort range (`30000-32767`) creates many iptables rules and can freeze the host.
- Host ports `< 1024` may require root/capabilities.
- On Docker Desktop (macOS/Windows), container IPs are **not** reachable from the host; use published host ports rather than relying on `LoadBalancer` `EXTERNAL-IP` values.

---

## Running k3d with Cilium (>= 1.20)

### Disable the default CNI at cluster creation

```bash
k3d cluster create cilium-lab \
  --servers 1 \
  --agents 2 \
  --api-port 6443 \
  --k3s-arg "--flannel-backend=none@server:*" \
  --k3s-arg "--disable-network-policy@server:*" \
  --k3s-arg "--disable-kube-proxy@server:*"
```

- `--flannel-backend=none` disables Flannel so another CNI can be installed. ([K3s network options](https://docs.k3s.io/installation/network-options))
- `--disable-network-policy` disables the embedded netpol controller to avoid conflicts with Cilium. ([K3s networking services](https://docs.k3s.io/networking/networking-services))
- `--disable-kube-proxy` lets Cilium fully replace kube-proxy. ([K3s server CLI](https://docs.k3s.io/cli/server))

### Install Cilium in the correct order

Create the cluster first, then install Cilium. Match k3s's default pod CIDR (`10.42.0.0/16`) and enable kube-proxy replacement:

```bash
cilium install --version 1.20.3 \
  --set kubeProxyReplacement=true \
  --set ipam.operator.clusterPoolIPv4PodCIDRList=10.42.0.0/16

cilium status --wait
```

Cilium's official docs cover K3s; the equivalent flags are passed to k3d via `--k3s-arg`. Reference: [Cilium K3s installation guide](https://docs.cilium.io/en/stable/installation/k3s/)

### Validate Cilium

```bash
cilium status
kubectl get nodes
cilium connectivity test
```

---

## Cilium Node IPAM: what it actually is

"Node IPAM" in Cilium is **not** the same as k3d port publishing, Cilium LB IPAM, or the Kubernetes controller-manager Node IPAM.

Cilium's [Node IPAM LoadBalancer](https://docs.cilium.io/en/stable/network/node-ipam/) advertises selected nodes' IP addresses directly in a `Service` of type `LoadBalancer`. It is useful when you cannot run Cilium L2 Announcements or BGP. It is disabled by default. It only sets `status.loadBalancer.ingress` IPs; it does **not** open host ports by itself. It works with Cilium's kube-proxy replacement, which terminates traffic on the node IP/port and forwards it to pods. It honors `node.kubernetes.io/exclude-from-external-load-balancers` and can be scoped with the `io.cilium.nodeipam/match-node-labels` annotation. Do **not** set `externalTrafficPolicy: Local` on services generated by Cilium's own Gateway API / Ingress implementation, because Cilium uses a dummy EndpointSlice; Traefik's own LoadBalancer service is not affected.

Do not confuse it with **Cilium LB IPAM** ([docs](https://docs.cilium.io/en/stable/network/lb-ipam/)), which allocates IPs from `CiliumLoadBalancerIPPool` objects and is usually advertised via L2/BGP, or with **k3d port publishing**, a Docker-level host-port mapping.

---

## Lab: Traefik ingress / Gateway API on host ports 80/443

This lab disables k3s ServiceLB and uses Cilium Node IPAM as the LoadBalancer implementation for upstream Traefik.

### 1. Create the cluster

```bash
k3d cluster create traefik-lab \
  --servers 1 \
  --agents 2 \
  --api-port 6443 \
  -p "80:80@loadbalancer" \
  -p "443:443@loadbalancer" \
  --k3s-arg "--flannel-backend=none@server:*" \
  --k3s-arg "--disable-network-policy@server:*" \
  --k3s-arg "--disable-kube-proxy@server:*" \
  --k3s-arg "--disable=servicelb@server:*" \
  --k3s-arg "--disable=traefik@server:*"
```

`--disable=servicelb` removes k3s's built-in LoadBalancer controller; Cilium Node IPAM takes its place. `--disable=traefik` removes the packaged Traefik so we can install the upstream chart.

### 2. Install Cilium with Node IPAM as the default LB implementation

```bash
cilium install --version 1.20.3 \
  --set kubeProxyReplacement=true \
  --set ipam.operator.clusterPoolIPv4PodCIDRList=10.42.0.0/16 \
  --set nodeIPAM.enabled=true \
  --set defaultLBServiceIPAM=nodeipam

cilium status --wait
```

`defaultLBServiceIPAM=nodeipam` makes LoadBalancer services without an explicit `loadBalancerClass` use Node IPAM.

### 3. Install Traefik via Helm

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --set service.type=LoadBalancer \
  --set ports.web.port=80 \
  --set ports.websecure.port=443
```

Wait until the service gets node IPs from Cilium Node IPAM:

```bash
kubectl -n traefik get svc traefik
```

### 4. Verify host access

Host ports 80/443 are mapped to the k3d load balancer, which forwards to all server nodes. Cilium's eBPF datapath routes traffic to the Traefik pods:

```bash
curl -I http://localhost/
# expect a 404 from Traefik until a route is created
```

### 5. Option A: expose an app with Ingress

```bash
kubectl create deployment whoami --image=traefik/whoami
kubectl expose deployment whoami --port=80 --target-port=80
```

```yaml
# whoami-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: whoami
  annotations:
    ingress.kubernetes.io/ssl-redirect: "false"
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: whoami
                port:
                  number: 80
```

```bash
kubectl apply -f whoami-ingress.yaml
curl http://localhost/
```

Ingress is simpler and stable, but the API is frozen and will not receive new features. ([Traefik Ingress provider](https://doc.traefik.io/traefik/providers/kubernetes-ingress/))

### 6. Option B: expose an app with Gateway API

Gateway API is the successor to Ingress, with a role-oriented resource model. For Traefik, install the Gateway API CRDs and enable the `kubernetesGateway` provider.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.3/standard-install.yaml

helm upgrade traefik traefik/traefik \
  --namespace traefik \
  --reuse-values \
  --set providers.kubernetesGateway.enabled=true
```

```yaml
# gateway-whoami.yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: traefik-gateway
  namespace: traefik
spec:
  gatewayClassName: traefik
  listeners:
    - name: http
      protocol: HTTP
      port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: whoami
  namespace: default
spec:
  parentRefs:
    - name: traefik-gateway
      namespace: traefik
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: whoami
          port: 80
```

```bash
kubectl apply -f gateway-whoami.yaml
kubectl get gateway -A
kubectl get httproute -A
curl http://localhost/
```

Reference: [Traefik Gateway provider](https://doc.traefik.io/traefik/providers/kubernetes-gateway/)

---

## Multi-agent and host-port caveats

`@loadbalancer` targets **server nodes only**. With Cilium kube-proxy replacement, traffic reaching a server node is forwarded to agent pods, so host access still works. Without kube-proxy replacement, mapping 80/443 to only servers will not reach pods on agents unless endpoints exist on those servers. Run Traefik as a DaemonSet or pin it to server nodes to guarantee coverage. Use `externalTrafficPolicy: Cluster`; `Local` can break cross-node forwarding.

---

## Validation and troubleshooting commands

```bash
# k3d state
k3d cluster list
k3d node list <cluster>
docker logs k3d-traefik-lab-serverlb

# Kubernetes / Cilium state
kubectl get nodes -o wide
kubectl -n kube-system get pods -l k8s-app=cilium
kubectl -n traefik get svc traefik
cilium status
cilium connectivity test

# Ingress / Gateway state
kubectl get ingress,gateway,httproute -A
kubectl describe gateway <name> -n <namespace>
kubectl describe httproute <name>

# Cilium agent logs
kubectl -n kube-system logs -l k8s-app=cilium --tail=100 -f
```

---

## References

Primary sources:

- k3d: <https://k3d.io/>
- k3d v5.9.0 `cluster create`: <https://k3d.io/v5.9.0/usage/commands/k3d_cluster_create/>
- k3d exposing services: <https://k3d.io/v5.9.0/usage/exposing_services/>
- k3d registries: <https://k3d.io/v5.9.0/usage/registries/>
- k3d nodefilter concepts: <https://k3d.io/v5.8.3/design/concepts/>
- k3s network options / custom CNI: <https://docs.k3s.io/installation/network-options>
- k3s packaged components and `--disable`: <https://docs.k3s.io/installation/packaged-components>
- k3s networking services: <https://docs.k3s.io/networking/networking-services>
- k3s server CLI: <https://docs.k3s.io/cli/server>
- Cilium K3s installation: <https://docs.cilium.io/en/stable/installation/k3s/>
- Cilium kube-proxy replacement: <https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/>
- Cilium Node IPAM LoadBalancer: <https://docs.cilium.io/en/stable/network/node-ipam/>
- Cilium LB IPAM: <https://docs.cilium.io/en/stable/network/lb-ipam/>
- Cilium Gateway API: <https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/>
- Traefik Kubernetes Ingress provider: <https://doc.traefik.io/traefik/providers/kubernetes-ingress/>
- Traefik Kubernetes Gateway provider: <https://doc.traefik.io/traefik/providers/kubernetes-gateway/>
- Kubernetes Gateway API: <https://gateway-api.sigs.k8s.io/>

Secondary source consulted but claims verified against official docs:

- Hagzag, "Cilium, Part 1 — Hands-On With eBPF Network Policies on k3d": <https://portfolio.hagzag.com/blog/reading-lists/cilium-in-practice/2025-11-08-cilium-part-1-k3d-lab/>
