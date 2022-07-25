# Configuring VMs

## Cloud VM (Debian 11)
```
sudo apt install wireguard
sudo ip link add dev wg0 type wireguard
sudo ip address add dev wg0 10.6.0.1/24
sudo wg setconf wg0 azure-wg.conf
sudo ip link set up dev wg0
sudo ip route add 10.6.66.0/24 via 10.6.0.2 dev wg0
```

### Wireguard Config
```
[Interface]
PrivateKey =
ListenPort = 51820
[Peer]
PublicKey = $CLIENT_KEY
AllowedIPs = 10.6.0.2/32,10.6.66.0/24
```

## Gateway VM (Debian 11)
Client VM traffic out through Wireguard connection to cloud VM.

### Network Namespace Config
```ip netns add lab

ip link add veth0 type veth peer name veth1 netns lab
ip netns exec lab ip addr add 10.42.0.65/24 dev veth1
ip netns exec lab ip link set dev lo up
ip netns exec lab ip link set dev veth1 up

ip link set dev veth0 up
ip link set veth0 master br0

ip link set eth1 netns lab
ip netns exec lab ip addr add 10.6.66.1/24 dev eth1
ip netns exec lab ip link set dev eth1 up

ip link add dev b40 type bridge
ip link set eth0 master br0
# WARNING: Lose network connectivity
ip addr del 10.42.0.64/24 dev eth0
# Restore local connectivity
ip addr add dev br0  10.42.0.64/24
# Restore internet connectivity
ip route add default via 10.42.0.1 dev br0

# Routing to namespace
ip route add 10.6.66.0/24 via 10.42.0.65 dev br0
```

### Wireguard Config
```
[Interface]
PrivateKey =
ListenPort = 51821
[Peer]
PublicKey =
Endpoint = $AZURE_IP:51820
AllowedIPs = 0.0.0.0/0
```

### nftables(iptables successor) Config

```
#!/usr/sbin/nft -f

flush ruleset

#create table ip lab { flags dormant; }
create table ip lab 

create chain ip lab output { type filter hook output priority 100; policy accept; }

create chain ip lab input { type filter hook input priority 100; policy drop; }
add rule ip lab input ct state invalid drop
add rule ip lab input ct state related,established accept
add rule ip lab input iifname lo accept
add rule ip lab input iifname != lo ip daddr 127.0.0.1/8 drop
add rule ip lab input ip protocol icmp accept
add rule ip lab input iifname eth0 tcp dport 22 accept

add rule ip lab input iifname wg0 accept

create chain ip lab forward { type filter hook forward priority 100; policy drop; }
add rule ip lab forward iifname eth0 oifname eth1 ip daddr 10.6.66.0/24 tcp port 22 accept
add rule ip lab forward iifname eth1 oifname eth0 ip daddr 10.42.0.0/24 ct state related,established accept

add rule ip lab forward iifname br0 oifname br0 accept
add rule ip lab forward oifname veth0 accept

create chain ip lab forward { type filter hook forward priority 100; policy drop; }
add rule ip lab forward iifname eth1 oifname veth1 ip daddr 10.42.0.0/24 ct state related,established accept
add rule ip lab forward iifname veth1 oifname eth1 accept
add rule ip lab forward iifname eth1 oifname veth1 accept
add rule ip lab forward iifname br0 oifname eth1 accept

add rule ip lab forward iifname eth1 oifname wg0 ip daddr != 10.42.0.0/24 accept
add rule ip lab forward iifname wg0 oifname eth1 ct state related,established accept

add rule ip lab forward iifname eth0 oifname veth0 ip accept

create chain ip lab nat { type nat hook postrouting priority 0; policy accept; }
add rule ip lab nat oifname eth1 ip saddr 10.42.0.0/24 snat to 10.6.66.1
```

```
flush ruleset

table ip lab {
	chain output {
		type filter hook output priority 100; policy accept;
	}

	chain forward {
		type filter hook forward priority 100; policy drop;
		iif eth0 oif veth0 accept
		iif veth0 oif eth0 ct state related,established accept
	}

	chain input {
		type filter hook input priority 100; policy drop;
		ct state invalid drop
		ct state established,related accept
		iifname "lo" accept
		iifname != "lo" ip daddr 127.0.0.0/8 drop
		ip protocol icmp accept
		tcp dport ssh accept
	}

	chain nat {
		type nat hook postrouting priority 0; policy accept;
	}
}
```
