# k3s Operational Reference

Scope: running K3s clusters with Cilium (>=1.20) as the CNI. This reference focuses on K3s-specific mechanics; it does not cover Rancher Manager, the Traefik ingress, ServiceLB, replacing containerd, or generic Kubernetes internals.

Sources are the [K3s documentation](https://docs.k3s.io/), the [k3s-io/k3s](https://github.com/k3s-io/k3s) repository, and the [k3s-io/kine](https://github.com/k3s-io/kine) project.

---

## Server and Agent Roles

- A **server** runs `k3s server` and hosts the Kubernetes control plane **and** the datastore. It also runs an embedded agent (kubelet, container runtime, CNI) unless started with `--disable-agent` (experimental).
- An **agent** runs `k3s agent`, has no datastore or control-plane components, and runs workloads.
- Both roles run the kubelet, container runtime, and CNI by default. ([Architecture](https://docs.k3s.io/architecture))

### Bootstrap Sequence

1. First server starts the cluster.
   - Single-node/SQLite: `K3S_TOKEN=<SECRET> k3s server`
   - HA embedded etcd: `K3S_TOKEN=<SECRET> k3s server --cluster-init --tls-san <FIXED_IP>`
2. Additional servers join via `K3S_TOKEN=<SECRET> k3s server --server https://<existing-server>:6443`.
3. Agents join via `K3S_TOKEN=<SECRET> k3s agent --server https://<server-or-fixed-ip>:6443`.

Critical flags must match across all servers: `--cluster-cidr`, `--service-cidr`, `--cluster-dns`, `--cluster-domain`, `--disable-kube-proxy`, `--disable-network-policy`, `--disable-helm-controller`, and every value passed to `--disable`. Mismatches cause `critical configuration value mismatch` errors when joining embedded etcd, or incorrect behavior with an external datastore. ([HA Embedded etcd](https://docs.k3s.io/datastore/ha-embedded), [HA External DB](https://docs.k3s.io/datastore/ha))

### Converting a Single-Node Cluster to etcd

Restart the single server with `--cluster-init`. If etcd files already exist on disk, datastore arguments are ignored on subsequent starts. ([HA Embedded etcd](https://docs.k3s.io/datastore/ha-embedded))

---

## Configuration: CLI Flags vs `/etc/rancher/k3s/config.yaml`

K3s loads configuration from:

- CLI flags
- `K3S_*` environment variables
- `/etc/rancher/k3s/config.yaml` by default
- Drop-in files from `/etc/rancher/k3s/config.yaml.d/*.yaml` in alphabetical order

The default config path can be changed with `--config` or `K3S_CONFIG_FILE`; when changed, the drop-in directory path is changed accordingly. ([Configuration Options](https://docs.k3s.io/installation/configuration))

### Mapping CLI to YAML

- Boolean flags become `true`/`false`.
- Repeatable flags become YAML lists.
- Keys match the CLI flag name without leading dashes.

Example:

```yaml
write-kubeconfig-mode: "0644"
tls-san:
  - "foo.local"
node-label:
  - "foo=bar"
cluster-init: true
```

### Precedence and Merge Behavior

- CLI arguments take precedence over config file values.
- For repeatable arguments, CLI values replace the entire list from the config file.
- When a key appears in multiple drop-in files, the last value wins.
- Append `+` to a key to merge into an existing string or list instead of replacing it. Once `+` is used for a key, later files must also use `+` to avoid overwriting the accumulated value. ([Configuration Options](https://docs.k3s.io/installation/configuration))

### Install Script Notes

The install script persists `INSTALL_K3S_EXEC`, `K3S_*` variables, and trailing arguments into the systemd/openrc service. Re-running the installer without passing the same values **loses** the previous values. Use `config.yaml` for configuration that should survive installer runs. ([Configuration Options](https://docs.k3s.io/installation/configuration))

---

## Join Token Lifecycle and Node Passwords

K3s uses three token types: ([k3s token CLI](https://docs.k3s.io/cli/token))

| Type | CLI / File | Notes |
|------|------------|-------|
| Server token | `--token` / `K3S_TOKEN` | Can join servers and agents. Written to `/var/lib/rancher/k3s/server/token` in secure format. Encrypts bootstrap data in the datastore. |
| Agent token | `--agent-token` / `K3S_AGENT_TOKEN` | Can join agents only. Written to `/var/lib/rancher/k3s/server/agent-token`. Defaults to the server token. |
| Bootstrap token | `k3s token create` | kubeadm-style, expiring token for agents. |

### Secure Token Format

Secure tokens look like `K10<cluster CA hash>::<credentials>`. The joining node downloads the CA bundle from `/cacerts`, verifies the hash, validates the server certificate, and only then sends credentials. Short tokens contain only the password and skip CA validation, which is vulnerable to MITM during join. ([k3s token CLI](https://docs.k3s.io/cli/token))

### Token Rotation

- Rotate the server token with `k3s token rotate`. All servers and any agents that originally joined with the old token must be restarted with the new token. Snapshots taken before rotation require the old token to restore. ([k3s token CLI](https://docs.k3s.io/cli/token))
- Agent token can be changed by updating `--agent-token` on all servers and restarting them; it is static and does not expire. ([k3s token CLI](https://docs.k3s.io/cli/token))
- Bootstrap tokens are created with `k3s token create --ttl <duration>` and support `--groups`/`--usages`. ([k3s token CLI](https://docs.k3s.io/cli/token))

### Node Password Implications

Agents register with the join token plus a randomly generated per-node password. The server stores this in a node password Secret. If a node is removed and later reinstalled with the same hostname, delete the old Node object (and therefore its node password Secret) before rejoining, otherwise registration may fail. ([Architecture](https://docs.k3s.io/architecture), [Uninstalling K3s](https://docs.k3s.io/installation/uninstall))

---

## Certificate Lifecycle and Rotation

### Leaf (Client/Server) Certificates

- Valid for 365 days from issuance.
- Automatically renewed on K3s startup if expired or within 120 days of expiry (90 days before the May 2025 releases: v1.33.1+k3s1, v1.32.5+k3s1, v1.31.9+k3s1, v1.30.13+k3s1).
- Renewal reuses existing keys and extends validity; to generate new keys use `k3s certificate rotate`.
- Check status: `k3s certificate check --output table`.
- Manual rotation: stop K3s, run `k3s certificate rotate [--service <name>]`, start K3s. Rotatable services include `admin`, `api-server`, `controller-manager`, `scheduler`, `k3s-controller`, `k3s-server`, `cloud-controller`, `etcd`, `auth-proxy`, `kubelet`, and `kube-proxy`. ([k3s certificate CLI](https://docs.k3s.io/cli/certificate))

### CA Certificates

- K3s generates self-signed CA certificates on first server startup; valid for 10 years; **not** automatically renewed.
- Authoritative CA certs and keys are stored in the datastore's bootstrap key, encrypted with a key derived from the server token (PBKDF2 + AES256-GCM + HMAC-SHA1). Copies are extracted to `/var/lib/rancher/k3s/server/tls` on server startup. ([k3s certificate CLI](https://docs.k3s.io/cli/certificate))
- Rotate CA certs with `k3s certificate rotate-ca`. Stage updated files in a separate directory and pass `--path=<dir>`; do not overwrite the in-use `/var/lib/rancher/k3s/server/tls`. Rotation can be non-disruptive if the same root CA is used; changing the root CA is disruptive and requires `--force`, reconfiguring nodes joined with secure tokens, and restarting pods to trust the new root. ([k3s certificate CLI](https://docs.k3s.io/cli/certificate))

### Custom CA Certificates

To use a custom PKI, place the required files in `/var/lib/rancher/k3s/server/tls` before first startup:

- `server-ca.crt`, `server-ca.key`
- `client-ca.crt`, `client-ca.key`
- `request-header-ca.crt`, `request-header-ca.key`
- `etcd/peer-ca.crt`, `etcd/peer-ca.key`, `etcd/server-ca.crt`, `etcd/server-ca.key` (required even when embedded etcd is not used)
- `service.key` (service-account token signing key; no corresponding certificate)

An example helper script is available at `contrib/util/generate-custom-ca-certs.sh`. ([k3s certificate CLI](https://docs.k3s.io/cli/certificate))

### Service-Account Issuer Key Rotation

The service-account token signing key is the RSA private key at `/var/lib/rancher/k3s/server/tls/service.key`. To rotate it without invalidating existing tokens, generate a new key, append the old key to the file, stage it in a separate directory, and run `k3s certificate rotate-ca --path=<dir>`. Restart all servers; agents and pods do not need to be restarted. ([k3s certificate CLI](https://docs.k3s.io/cli/certificate))

---

## Datastore Options and Kine

K3s uses [Kine](https://github.com/k3s-io/kine) as an etcd shim. Available backends: ([Cluster Datastore](https://docs.k3s.io/datastore), [Kine README](https://github.com/k3s-io/kine/blob/master/README.md))

| Backend | HA? | How to select |
|---------|-----|---------------|
| Embedded SQLite | No (single server only) | Default when no other datastore is configured and no etcd files exist. |
| Embedded etcd | Yes (odd number of servers) | Start first server with `--cluster-init`; join others with `--server`. |
| External SQL (MySQL, MariaDB, PostgreSQL) | Yes (2+ servers + external DB) | Set `--datastore-endpoint` on every server. |
| External etcd | Yes | Set `--datastore-endpoint` to etcd endpoints. |
| NATS (embedded or external JetStream) | Through JetStream replication | Works through Kine with a `nats://` endpoint; not listed as a certified backend in the official k3s datastore docs. |

### Embedded etcd

- Requires an odd number of server nodes for quorum.
- Adding one node to an odd-sized cluster does **not** improve fault tolerance.
- Embedded etcd is I/O intensive; avoid SD cards. ([HA Embedded etcd](https://docs.k3s.io/datastore/ha-embedded))

### External SQL Datastores

K3s officially certifies: ([Cluster Datastore](https://docs.k3s.io/datastore))

- PostgreSQL 15.12, 16.7, 17.3
- MySQL 8.0, 8.4
- MariaDB 10.11, 11.4
- etcd 3.5.21

Connection examples:

```yaml
# PostgreSQL
datastore-endpoint: "postgres://user:pass@host:5432/dbname"

# MySQL
datastore-endpoint: "mysql://user:pass@tcp(host:3306)/dbname"
```

TLS client auth: `--datastore-cafile`, `--datastore-certfile`, `--datastore-keyfile` (or env vars `K3S_DATASTORE_*`). Prefer environment variables to avoid exposing credentials in process listings. ([Cluster Datastore](https://docs.k3s.io/datastore))

SQL caveats:

- Prepared statements are required; connection poolers such as PgBouncer may need extra configuration.
- MySQL/MariaDB multi-master setups with `auto_increment_increment` or `auto_increment_offset` > 1 are not supported.
- Databases created before May 2024 may need the `KINE_SCHEMA_MIGRATION=1` environment variable set to avoid the 2,147,483,647 revision limit. ([Known Issues](https://docs.k3s.io/known-issues))

### NATS Backend

Kine's NATS backend uses NATS JetStream Key-Value. K3s exposes it through the same `--datastore-endpoint` flag. Endpoint format: ([Kine NATS example](https://github.com/k3s-io/kine/blob/master/examples/nats.md))

```
nats://[[<auth>@]<host>]:<port>[?<params>]
```

Useful query parameters:

- `bucket` (default `kine`)
- `replicas` (default `1`)
- `revHistory` (default `10`)
- `noEmbed=true` to connect to an external NATS server
- `serverConfig=/path/to/server.conf` to configure the embedded NATS server
- Multiple URLs can be comma-separated; only the first URL's query parameters are evaluated.

Caveats: NATS support is less prominently documented than SQL/etcd in the K3s docs; the authoritative behavior is defined by Kine. SQL and NATS external datastores do not use etcd quorum semantics, but they make the control plane dependent on the external datastore's availability.

### Backup and Restore

- **SQLite**: copy/restore `/var/lib/rancher/k3s/server/db/` plus the server token.
- **External SQL/etcd**: back up the database using native database tools plus the K3s server token.
- **Embedded etcd**: use `k3s etcd-snapshot` for backup/restore. ([Backup and Restore](https://docs.k3s.io/datastore/backup-restore), [k3s etcd-snapshot CLI](https://docs.k3s.io/cli/etcd-snapshot))

The server token is required for restore because it decrypts bootstrap data in the datastore. ([Backup and Restore](https://docs.k3s.io/datastore/backup-restore))

---

## Air-Gapped Install and Image Sources

Three high-level approaches: private registry, manually deploy images, or embedded registry mirror. ([Air-Gap Install](https://docs.k3s.io/installation/airgap))

### Private Registry Method

1. Download the `k3s-airgap-images-<arch>.tar.zst` for the target version from the release page.
2. Import and retag images into the private registry.
3. Configure `/etc/rancher/k3s/registries.yaml` on every node with mirrors and TLS/auth.
4. Install the matching K3s binary and run `INSTALL_K3S_SKIP_DOWNLOAD=true ./install.sh`.

For agents: `INSTALL_K3S_SKIP_DOWNLOAD=true K3S_URL=https://<SERVER>:6443 K3S_TOKEN=<TOKEN> ./install.sh`. ([Air-Gap Install](https://docs.k3s.io/installation/airgap))

### Manual Image Load

Place the air-gap tar in `/var/lib/rancher/k3s/agent/images/` on each node before starting K3s. The embedded containerd will load images from the tar. ([Air-Gap Install](https://docs.k3s.io/installation/airgap))

### Embedded Registry Mirror (Spegel)

Enable with `--embedded-registry` on servers (or `embedded-registry: true` in `config.yaml`). When enabled, all nodes expose a local OCI registry on port 6443 and a peer-to-peer index on port 5001. Nodes must reach each other on TCP 5001 and 6443. Registries to mirror are listed in `/etc/rancher/k3s/registries.yaml`. The embedded registry is read-only and assumes equal trust among all cluster members. ([Embedded Registry Mirror](https://docs.k3s.io/installation/registry-mirror))

### Upgrading in an Air-Gapped Environment

1. Place the new air-gap tar in `/var/lib/rancher/k3s/agent/images/` and remove the old tar.
2. Replace the K3s binary with the new version.
3. Re-run the install script with the same environment variables, or restart the service. ([Air-Gap Install](https://docs.k3s.io/installation/airgap))

### Private Registry Configuration (`registries.yaml`)

File location: `/etc/rancher/k3s/registries.yaml`. Example: ([Private Registry Configuration](https://docs.k3s.io/installation/private-registry))

```yaml
mirrors:
  docker.io:
    endpoint:
      - "https://registry.example.com:5000"
configs:
  "registry.example.com:5000":
    auth:
      username: xxx
      password: xxx
    tls:
      ca_file: /path/to/ca.crt
```

- Rewrites apply only when the mirror endpoint differs from the default endpoint.
- Use `"*"` as a wildcard mirror (must be quoted).
- Use `--disable-default-registry-endpoint` to prevent falling back to the upstream registry for configured mirrors.

---

## Auto-Deploying Manifests and HelmChart AddOns

On every server, files in `/var/lib/rancher/k3s/server/manifests` are applied like `kubectl apply` on startup and when changed. They are tracked as `AddOn` custom resources in `kube-system`. Deleting a file does **not** delete the resources it created. ([Managing Packaged Components](https://docs.k3s.io/installation/packaged-components))

### File Naming

The `AddOn` name is the file basename. Names must be unique, RFC 1123 subdomain-compliant, and must not collide with packaged component names even if those components are disabled. ([Managing Packaged Components](https://docs.k3s.io/installation/packaged-components))

### Disabling Manifests

- `--disable=<name>` uninstalls the AddOn and deletes the source manifest. Packaged components include `coredns`, `traefik`, `local-storage`, `metrics-server`; `servicelb` can also be disabled this way for historical reasons.
- A `<manifest>.yaml.skip` file causes K3s to ignore that manifest, but does not remove already-deployed resources. ([Managing Packaged Components](https://docs.k3s.io/installation/packaged-components))

### HelmChart and HelmChartConfig

K3s includes a Helm controller driven by the `HelmChart` CRD (`helm.cattle.io/v1`). Drop a `HelmChart` manifest into the manifests directory to install/upgrade a chart automatically. ([Helm AddOns](https://docs.k3s.io/add-ons/helm))

Key `HelmChart` fields:

- `spec.chart` / `spec.repo` / `spec.version`
- `spec.targetNamespace` / `spec.createNamespace`
- `spec.valuesContent` (inline values)
- `spec.valuesSecrets` (values from Secrets in the same namespace)
- `spec.set` (highest precedence)
- `spec.authSecret` / `spec.dockerRegistrySecret` / `spec.repoCAConfigMap`
- `spec.bootstrap: true` for charts needed before the cluster is fully online (e.g., a cloud controller manager)

Override packaged chart values with a `HelmChartConfig` of the same name and namespace:

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: coredns
  namespace: kube-system
spec:
  valuesContent: |-
    # Chart-specific values go here.
```

Precedence (lowest to highest): chart defaults, HelmChart `valuesContent`, HelmChart `valuesSecrets`, HelmChartConfig `valuesContent`, HelmChartConfig `valuesSecrets`, HelmChart `set`. ([Helm AddOns](https://docs.k3s.io/add-ons/helm))

---

## Build from Source and Version Compatibility

### Building

Prerequisites: `make`, Docker, BuildKit/Buildx. ([BUILDING.md](https://github.com/k3s-io/k3s/blob/master/BUILDING.md))

```bash
git clone --depth 1 https://github.com/k3s-io/k3s.git
cd k3s
make binary                 # ./dist/artifacts/k3s
make multiarch-binary       # buildx multi-arch
SKIP_VALIDATE=true make     # skip linting with uncommitted changes
```

If `go.mod` is modified, run `go mod tidy` before building. ([BUILDING.md](https://github.com/k3s-io/k3s/blob/master/BUILDING.md))

### Versioning

K3s release names reflect the upstream Kubernetes version, e.g. `v1.27.4+k3s1` is based on Kubernetes `v1.27.4`. Patch releases increment the `+k3sN` suffix. ([README.md](https://github.com/k3s-io/k3s/blob/master/README.md))

### Upgrade Rules

- Upgrade servers first, one at a time, then agents.
- Do not skip Kubernetes minor versions; the upstream version skew policy applies.
- Release channels: `stable` (default), `latest`, and per-minor channels such as `v1.33`. ([Manual Upgrades](https://docs.k3s.io/upgrades/manual))

### Snapshot Restore Compatibility

A snapshot can be restored to a K3s version that is the same or newer (patch or minor), as long as the Kubernetes version skew policy is respected. Do not restore a snapshot from an older K3s version than you could directly upgrade from. ([k3s etcd-snapshot CLI](https://docs.k3s.io/cli/etcd-snapshot))

---

## Tailscale VPN Integration (Experimental)

Available since v1.27.3, v1.26.6, and v1.25.11. ([Distributed/Multicloud](https://docs.k3s.io/networking/distributed-multicloud))

Setup steps:

1. Generate a Tailscale auth key in the admin console (can be reusable).
2. Add the cluster pod CIDR to Tailscale `autoApprovers` routes.
3. Install Tailscale on each node.
4. Start K3s with `--vpn-auth="name=tailscale,joinKey=$AUTH_KEY"` (or `--vpn-auth-file`).
5. Use `--node-external-ip=<TailscaleIP>` on every node; agents use the server's Tailscale IP as `--server`.
6. Approve the nodes and routes in the Tailscale console (unless auto-approvers are configured).

If Tailscale ACLs are enabled, allow pod-to-pod traffic. Example ACL for nodes tagged `testing-k3s` and pod CIDR `10.42.0.0/16`:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:testing-k3s", "10.42.0.0/16"],
      "dst": ["tag:testing-k3s:*", "10.42.0.0/16:*"]
    }
  ]
}
```

Caveats: running multiple clusters on the same Tailscale network requires non-overlapping pod CIDRs or strict ACLs. ([Distributed/Multicloud](https://docs.k3s.io/networking/distributed-multicloud))

---

## Networking and Firewall Requirements

### Node-to-Node Ports

| Protocol | Port | Scope | Purpose |
|----------|------|-------|---------|
| TCP | 6443 | All nodes → servers | K3s supervisor and Kubernetes API |
| TCP | 6443 | All nodes ↔ all nodes | Embedded registry mirror (Spegel) |
| TCP | 2379-2380 | Servers ↔ servers | Embedded etcd peer/client |
| UDP | 8472 | All nodes ↔ all nodes | Cilium VXLAN when overlay mode is enabled |
| TCP | 10250 | All nodes ↔ all nodes | Kubelet metrics/API |
| TCP | 5001 | All nodes ↔ all nodes | Embedded registry mirror peer index |

The k3s Flannel WireGuard ports 51820/51821 are not opened for the Cilium design. ([Requirements](https://docs.k3s.io/installation/requirements))

### Local Ports to Avoid

K3s and Kubernetes components listen on loopback for internal traffic. Avoid using these for NodePort/services or other workloads: 2381, 2382, 6444, 10010, 10248, 10249, 10250, 10256, 10257, 10258, 10259. ([Requirements](https://docs.k3s.io/installation/requirements))

### Firewalld

If firewalld must stay enabled, the minimum rules are: ([Requirements](https://docs.k3s.io/installation/requirements))

```bash
firewall-cmd --permanent --add-port=6443/tcp
firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16
firewall-cmd --reload
```

Adjust CIDRs if `--cluster-cidr` or `--service-cidr` are customized.

## Disabling the Default CNI for Cilium

Since Cilium (>=1.20) is the intended CNI, disable K3s Flannel and the bundled network-policy controller:

```yaml
# /etc/rancher/k3s/config.yaml
flannel-backend: none
disable-network-policy: true
```

If Cilium is also replacing kube-proxy, add:

```yaml
disable-kube-proxy: true
```

After the server starts, install Cilium. If running agentless servers, set `--egress-selector-mode=pod` or `cluster` so the apiserver can reach cluster services and webhooks. ([Basic Network Options](https://docs.k3s.io/networking/basic-network-options))

---

## Quick Decision Checklist

- **Single control plane, simple setup**: use embedded SQLite; back up `/var/lib/rancher/k3s/server/db/` and the server token.
- **HA control plane**: choose embedded etcd (odd server count) or an external datastore (2+ servers).
- **External datastore**: prefer PostgreSQL/MySQL/etcd for production; treat NATS as a Kine-level option until support is confirmed for the target k3s release.
- **Air gap**: use air-gap image tar + private registry or embedded registry mirror; keep binary and tar versions matched.
- **Join security**: use secure tokens (`K10...`) when possible; rotate server token with `k3s token rotate`; remember snapshots taken before rotation need the old token.
- **Reusing a hostname**: delete the old Node and its node password Secret before rejoining.
- **Certificates**: monitor `k3s certificate check`; plan manual CA rotation before the 10-year CA expiry.
- **Cilium**: disable Flannel and network policy; optionally disable kube-proxy.
