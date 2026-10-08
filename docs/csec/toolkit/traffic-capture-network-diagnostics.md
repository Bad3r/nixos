# Pentesting Toolkit: Traffic Capture & Network Diagnostics

[Back to Pentesting Toolkit](../toolkit.md)

## Traffic Capture & Network Diagnostics

- iptables
  - run..: `iptables -L -nv`
  - Repo.: <https://git.netfilter.org/iptables/>
  - Docs.: <https://www.netfilter.org/documentation/>
  - Desc.: Legacy Netfilter rule administration for lab routing and isolation.
- nftables
  - run..: `nft list ruleset`
  - Repo.: <https://git.netfilter.org/nftables/>
  - Docs.: <https://wiki.nftables.org/>
  - Desc.: Modern Netfilter rule administration for lab routing and isolation.
- netcat
  - run..: `nc -lvnp 4444`
  - Repo.: <https://github.com/libressl/portable>
  - Docs.: <https://man.openbsd.org/nc.1>
  - Desc.: Raw TCP/UDP read/write for port testing, banner grabbing, and pivots; this attribute packages the LibreSSL/OpenBSD-derived `nc` (not Hobbit's nc110).
- socat
  - run..: `socat TCP-LISTEN:1234 EXEC:/bin/bash`
  - Repo.: <http://www.dest-unreach.org/socat/>
  - Docs.: <http://www.dest-unreach.org/socat/doc/socat.html>
  - Desc.: Bidirectional data relay between sockets, files, and processes.
- tcpdump
  - run..: `tcpdump -i $iface -w out.pcap`
  - Repo.: <https://github.com/the-tcpdump-group/tcpdump>
  - Docs.: <https://www.tcpdump.org/manpages/tcpdump.1.html>
  - Desc.: Command-line packet capture.
- wireshark
  - run..: `wireshark`
  - Repo.: <https://gitlab.com/wireshark/wireshark>
  - Docs.: <https://www.wireshark.org/docs/>
  - Desc.: GUI packet analyzer with deep protocol dissectors.
