# WireGuard Deployment

The stack runs `ngoduykhanh/wireguard-ui` with a dedicated Docker network (`wg`, subnet `10.42.42.0/24`).  
WireGuard clients use `10.8.0.0/24` and Pi-hole stays in the host LAN (`192.168.178.0/24`). Because the VPN network only
exists inside the container, the host needs an explicit route so replies reach the WireGuard interface.

## Ports

- `51820/udp` — forwarded from the host to the container, used by WireGuard peers
- `wg.home` (HTTPS via Traefik on port 443, HTTP redirect on port 80) — WireGuard UI, Traefik proxies to the container on port `5000`

## Host Route Requirement

1. Make sure the container still has the static IP `10.42.42.42` (defined in `docker-compose.wg.yaml`). You can also verify it via:

   ```bash
   docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' wireguard
   ```

2. Add (or update) the route on the host so that traffic to the VPN subnet goes through the container:

   ```bash
   sudo ip route replace 10.8.0.0/24 via 10.42.42.42
   ip route show 10.8.0.0/24
   ```

Without this route, DNS queries hit Pi-hole, but replies never find their way back into the VPN.

## Persist the Route with systemd

The repository ships `systemd/wireguard-route.service`, which waits for Docker, checks that the container is reachable,
and installs the route persistently. To use it on the host:

```bash
sudo cp systemd/wireguard-route.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now wireguard-route.service
sudo systemctl status wireguard-route.service
```

Adjust the IP addresses inside the unit file if you ever change the WireGuard network or container address.

## Verifying WireGuard

- `docker exec wireguard wg show` — verify that the interface is up and clients have recent handshakes
- `ip route show 10.8.0.0/24` — confirm the host is routing VPN replies through the container
