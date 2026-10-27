# Configuration reference

The authoritative configuration contract is the [2.5.1 JSON schema](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/schema/2/ifstate.conf.schema.json). The examples below use Nix; YAML uses exactly the same keys and value shapes.

## Configuration map

Top-level sections are `parameters`, `interfaces`, `routing`, `namespaces`, `sysctl`, `sysctl_conf`, `bpf`, and `mac_seed`; `interfaces` is required. Each namespace can contain its own `interfaces`, `routing`, `sysctl`, and `bpf` sections.

```nix
networking.ifstate.settings = {
  parameters = {
    defaults = [];
    ignore = {};
    hooks = {};
  };
  interfaces = {};
  routing = {
    routes = [];
    rules = [];
  };
  namespaces = {};
};
```

Use upstream examples for the exact attributes of a link kind rather than guessing netlink names. [2.5 examples](https://ifstate.net/2.5/examples/) · [schema](https://ifstate.net/schema/2/ifstate.conf.schema.json)

## Physical interfaces and stable identity

`kind = "physical"` means IfState must find an existing device; it cannot create one. Registry matching tries `identify`, then a configured permanent link address, then the interface name. Generate candidates on the real host:

```bash
ifstatecli identify
```

```nix
interfaces.uplink = {
  addresses = ["192.0.2.10/24"];
  identify = {
    parent_dev_name = "0000:06:00.0";
    parent_dev_bus_name = "pci";
  };
  link = {
    kind = "physical";
    state = "up";
  };
};
```

Available identify attributes include `perm_address`, `parent_dev_name`, `parent_dev_bus_name`, `phys_port_id`, `phys_port_name`, `phys_switch_id`, and device-tree `of_node`. If no device matches, IfState cannot create the physical link; inspect the journal and `identify` output instead of assuming apply succeeded. [Identification source](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/util.py) · [Link matching](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/link/base.py)

## Bonds, bridges, and VLANs

Declare every member and give it one master. Physical bond/bridge members normally carry no addresses of their own; put addressing on the aggregator or VLAN child.

```nix
interfaces = {
  bond0 = {
    link = {
      kind = "bond";
      state = "up";
      bond_mode = "802.3ad";
      bond_ad_lacp_rate = "fast";
      bond_xmit_hash_policy = "layer3+4";
      bond_miimon = 100;
    };
  };
  lom1 = {
    identify = {
      parent_dev_name = "0000:06:00.0";
      parent_dev_bus_name = "pci";
    };
    link = {
      kind = "physical";
      state = "up";
      master = "bond0";
    };
  };
  lom2 = {
    identify = {
      parent_dev_name = "0000:06:00.1";
      parent_dev_bus_name = "pci";
    };
    link = {
      kind = "physical";
      state = "up";
      master = "bond0";
    };
  };
  mgmt = {
    addresses = ["192.0.2.80/24"];
    link = {
      kind = "vlan";
      state = "up";
      link = "bond0";
      vlan_id = 100;
      vlan_protocol = "802.1q";
    };
  };
};
```

A bridge uses `kind = "bridge"` and member links use `master = "br0"`. Set `br_stp_state = 0` when intentionally disabling STP, not as a default aesthetic choice. Bridge-port and bridge-VLAN settings live under `brport` and `brvlan`. [LACP/HAProxy example](https://ifstate.net/2.5/examples/haproxy/) · [Bridge source](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/link/base.py)

## Addresses, routes, rules, and sysctls

Addresses are CIDR strings. IfState adds missing addresses and removes non-ignored extras from managed interfaces. Dynamic addresses are preserved by default; changing `parameters.ignore.ipaddr_dynamic` makes cleanup more aggressive.

```nix
routing = {
  routes = [
    {
      to = "198.51.100.128/25";
      via = "198.51.100.1";
      dev = "outside";
      table = 100;
      preference = 50;
    }
    {
      to = "0.0.0.0/0";
      via = "fe80::defa"; # IPv4 route via an IPv6 nexthop
      dev = "outside";
    }
  ];
  rules = [
    {
      from = "192.0.2.10/32";
      table = 100;
      priority = 100;
    }
  ];
};
```

Route attributes include `to`, `via`, `dev`, `src`, `table`, `scope`, `proto`, `preference`, `onlink`, `type`, and `multipath`. IfState's default route protocol is 3 (`boot`). Rules support source/destination selectors, interfaces, fwmark, IP protocol, action, table, and priority. Avoid duplicate writers for the same prefix or rule. [Routing source](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/routing/__init__.py) · [Routing guide](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/docs/docs/routing.md)

IfState 2.5 adds `sysctl_conf` for free-form `sysctl.conf`-style network keys. For example:

```nix
sysctl_conf.net = {
  ipv4.ip_forward = 1;
  ipv6.conf.all.forwarding = 1;
};
```

Per-interface structured sysctls and top-level `sysctl` are also available. IfState writes `/proc/sys/net/...` directly and retries global keys after link creation when a lazily loaded module introduces them. [Sysctl guide](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/docs/docs/sysctl.md) · [Sysctl source](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/sysctl/__init__.py)

## Network namespaces and veth pairs

Declare the namespace and both ends of a cross-namespace veth. `peer_netns = null` means the root namespace; references such as `link_netns` and `master_netns` follow the same convention.

```nix
let
  netns = "example";
in {
  networking.ifstate.settings = {
    namespaces."${netns}".interfaces.veth0 = {
      addresses = ["192.0.2.2/32"];
      link = {
        kind = "veth";
        state = "up";
        peer = "veth1";
        peer_netns = null;
        address = "12:de:ad:be:ef:00";
      };
    };
    interfaces.veth1 = {
      link = {
        kind = "veth";
        state = "up";
        peer = "veth0";
        peer_netns = netns;
        address = "12:de:ad:be:ef:10";
      };
    };
    routing.routes = [
      {
        to = "192.0.2.2/32";
        via = "fe80::10de:adff:febe:ef00";
        dev = "veth1";
      }
    ];
  };
}
```

The fixed MACs make the IPv6 EUI-64 link-local nexthop predictable. Bind a systemd service with `serviceConfig.NetworkNamespacePath = "/var/run/netns/example"`, or point a NixOS container's `networkNamespace` at that path. IfState must run in the root namespace. Configured-away namespaces can be deleted; check the dry run for resident-process warnings. [Namespace guide](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/docs/docs/namespaces.md) · [NixOS wiki example](https://wiki.nixos.org/wiki/IfState)

## WireGuard

Peers form an attrset keyed by base64 public key. Use runtime secret includes and open the UDP listen port in the firewall.

```nix
interfaces.wg0 = {
  addresses = ["10.200.0.1/24"];
  link = {
    kind = "wireguard";
    state = "up";
  };
  wireguard = {
    private_key = "!include /run/secrets/wg0-private";
    listen_port = 51820;
    peers."PEER_BASE64_PUBLIC_KEY" = {
      endpoint = "192.0.2.2:51820";
      allowedips = ["10.200.0.0/24"];
      persistent_keepalive_interval = 25;
    };
  };
};
```

- `wireguard.table = N` derives one route per peer AllowedIP into table `N`. These are static IfState routes, not routes learned by FRR.
- `link.bind_netns = "outside"` binds the tunnel's underlying socket in another namespace. Changing the bind side recreates the link.
- Endpoints are applied after routes so endpoint resolution can use the new network state. Bare endpoint IPs default to port 51820.
- Removing a peer from settings removes it from the interface on apply.
- AllowedIPs are cryptokey routing. One peer's prefixes can shadow another's on the same interface; use separate interfaces for independent full-table paths.

[WireGuard example](https://ifstate.net/2.5/examples/wireguard/) · [WireGuard source](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/wireguard/__init__.py)

## Defaults and ignores

Built-in cleanup defaults match every interface not covered by an earlier user default. User `parameters.defaults` is an ordered list; the first matching entry wins. Use a specific default to alter cleanup for a class such as keepalived-controlled links:

```nix
parameters.defaults = [
  {
    match = [{ifname = "^HA-.+$";}];
    clear_addresses = true;
  }
];
```

Use ignores to declare another owner's objects. Examples:

```nix
parameters.ignore = {
  ifname = [
    "^vnet"      # libvirt/QEMU taps
    "^tap"       # other VM taps
    "^cilium_"   # Cilium datapath
    "^lxc"       # Cilium endpoint links
  ];
  routes = [
    {proto = 196;} # FRR staticd; alternatively declare the routes here
  ];
};
```

Built-in interface ignores cover common Docker, veth, PPP, libvirt bridge, and VRRP names. They do not cover every runtime. `showall` displays the merged built-in and user rules. Do not ignore protocol 3 routes: that hides IfState's own declared routes from reconciliation. [Defaults](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/docs/docs/defaults.md) · [Built-in ignore definitions](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/src/libifstate/parser/base.py)

## DHCP hooks

The module rejects global `networking.useDHCP`; DHCP belongs in an interface hook. The hook runs inside the interface's namespace and VRF with `IFS_IFNAME`, `IFS_NETNS`, and related environment variables.

```nix
{lib, pkgs, ...}: {
  networking.ifstate.settings = {
    parameters.hooks.dhcp.script = pkgs.writeScript "ifstate-udhcpc" ''
      ${lib.getExe' pkgs.busybox "udhcpc"} --quit --now -i "$IFS_IFNAME" -b --script ${pkgs.busybox}/default.script
    '';
    interfaces.eth1 = {
      addresses = [];
      hooks = [{name = "dhcp";}];
      link = {
        kind = "physical";
        state = "up";
      };
    };
  };
}
```

Hooks have start/stop/check actions, persistent state under `/run/libifstate/hooks`, and a default three-second timeout. A hook failure is an apply failure to diagnose, not a successful lease. [Hook guide](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/docs/docs/hooks.md) · [Hook examples](https://codeberg.org/routerkit/ifstate/src/tag/2.5.1/ex/hooks)
