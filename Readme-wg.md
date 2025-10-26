# WireGuard + Pi-hole Integration (Bridge-Mode)

Dieses System nutzt:
- **wg-easy** (Docker, Bridge-Netz, z. B. `172.19.0.0/16`)
- **Pi-hole** (im Hostnetz `192.168.178.0/24`)
- **WireGuard-Clients** (z. B. `10.8.0.0/24`)

## Problem

Im Bridge-Modus existiert das WireGuard-VPN (`10.8.0.0/24`) nur **innerhalb des Containers**.  
Der Host kennt dieses Netz nicht und weiß daher nicht, wohin Antworten für 10.8.x.x geschickt werden müssen.  
Ergebnis: DNS-Anfragen erreichen Pi-hole, aber Antworten gehen ins Leere.

## Lösung

Der Host muss wissen, dass alle Pakete für das WireGuard-VPN über den `wg-easy`-Container geroutet werden.  
Zusätzlich muss die Rückroute/NAT-Freigabe per `iptables` gesetzt werden, damit Pakete aus dem Hostnetz wieder in das VPN-Netz gelangen.

---

## 1️⃣ Route auf dem Host hinzufügen

> Diese Route sorgt dafür, dass Pakete für `10.8.0.0/24` über den `wg-easy`-Container (`172.19.0.3`) laufen.

```bash
sudo ip route add 10.8.0.0/24 via 172.19.0.3


docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' wg-easy                        10.42.42.42172.18.0.4                           johannes@debian:~/docker/homeserver$ sudo ip route add 10.8.0.0/24 via 172.18.0.4               [sudo] Passwort für johannes:                   johannes@debian:~/docker/homeserver$ sudo apt install iptables-persistent                       sudo netfilter-persistent save                  iptables-persistent ist schon die neueste Version (1.0.23).                                     Zusammenfassung:                                  Aktualisiere: 0, Installiere: 0, Entferne: 0, Aktualisiere nicht: 12                          run-parts: executing /usr/share/netfilter-persistent/plugins.d/15-ip4tables save                run-parts: executing /usr/share/netfilter-persistent/plugins.d/25-ip6tables save
