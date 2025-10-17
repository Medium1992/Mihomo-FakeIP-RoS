# Mihomo-FakeIP-RoS
This repository provides a Mihomo build with an integrated configuration, designed for deployment on MikroTik RouterOS via containerization, utilizing DNS static forwarding and the native RouterOS tunneling features.

## Example Usage

This example demonstrates how to integrate the `mihomo-fakeip-ros` container with MikroTik RouterOS to enable fake DNS forwarding. Fake IPs are issued for specific domains, routed back to the container, and outgoing traffic can be directed to any destination (including standard RouterOS tunnels).

### 1. Create a container interface

```bash
/interface/veth/add name=fakeip address=192.168.255.1/31 gateway=192.168.255.0
```

### 2. Assign the interface address to MikroTik

```bash
/ip/address/add address=192.168.255.0/31 interface=fakeip
```

### 3. Create DNS forwarders with the container’s IP address

```bash
/ip/dns/forwarders/add name=fakeip dns-servers=192.168.255.1 verify-doh-cert=no
```

### 4. Add environment variables

Customize these environment variables as needed to control the fake IP behavior and logging:

| Variable       | Description                              | Example Value       |
|----------------|------------------------------------------|---------------------|
| FAKE_IP_RANGE  | Pool of addresses used for fake IPs      | 198.18.0.0/15       |
| TTL_FAKEIP     | TTL for fake IP entries                  | 1                   |
| LOGLEVEL       | Log level for mihomo                     | silent              |

```bash
/container/envs
add key=FAKE_IP_RANGE list=fakeip value=198.18.0.0/15
add key=LOGLEVEL list=fakeip value=silent
add key=TTL_FAKEIP list=fakeip value=1
```

### 5. Pull and run the container

```bash
/container/add remote-image="ghcr.io/medium1992/mihomo-fakeip-ros" envlists=fakeip interface=fakeip root-dir=Containers/fakeip start-on-boot=yes
```

or

```bash
/container/add remote-image="registry-1.docker.io/medium1992/mihomo-fakeip-ros" envlists=fakeip interface=fakeip root-dir=Containers/fakeip start-on-boot=yes
```

> **Note**: For AMD v1 or v2 architectures, specify the appropriate tag. Check available tags at: Docker Hub or github. Older VPS hosts (e.g., Xeon E5 series) often require the v2 tag.

### 6. Add a route for fake IPs to the container’s gateway

```bash
/ip/route/add dst-address=198.18.0.0/15 gateway=192.168.255.1
```

### 7. Create a DNS address list to exclude from routing

```bash
/ip/firewall/address-list
add address=1.1.1.1 list=DNS
add address=9.9.9.9 list=DNS
add address=149.112.112.112 list=DNS
add address=104.16.248.249 list=DNS
add address=104.16.249.249 list=DNS
add address=8.8.8.8 list=DNS
add address=8.8.4.4 list=DNS
```

> **Note**: This list prevents routing loops by excluding upstream DNS servers from further routing.

### 8. Add a routing table for container traffic

```bash
/routing/table/add name=fakeip fib
```

### 9. Example mangle rules

```bash
/ip/firewall/mangle
add action=mark-connection chain=prerouting connection-mark=no-mark dst-address-list=!DNS dst-address-type=!local new-connection-mark=fakeip src-address=192.168.255.1
add action=mark-routing chain=prerouting connection-mark=fakeip in-interface=fakeip new-routing-mark=fakeip passthrough=no
```

### 10. Add domains for fake IP resolution

```bash
/ip/dns/static/add type=FWD forward-to=fakeip match-subdomain=yes name=googlevideo.com
```

> **Note**: Repeat this command for additional domains that should resolve to fake IPs.

### 11. Summary and final configuration

This configuration issues fake IPs for specified domains via `FWD` rules, routes them back to the container, and allows outgoing traffic to be directed anywhere, including standard RouterOS tunnels.

```bash
/ip/route/add dst-address=0.0.0.0/0 gateway=XXX.XXX.XXX.XXX routing-table=fakeip
```

> **Note**: Replace XXX.XXX.XXX.XXX with your actual gateway to complete the routing setup.
