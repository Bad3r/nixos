# Detect and block protocol mismatches on a firewall port

Use payload inspection when a port number alone is not enough to identify the
expected application protocol. For example, TCP port 443 can be reserved for a
TLS-terminating HTTPS service, while cleartext HTTP or another application
protocol on that port is logged and dropped.

Treat the examples below as packet-signature controls, not as a complete
application firewall. `iptables` and nftables normally inspect individual
packets. They do not reassemble a TCP stream, implement the TLS state machine,
verify certificates, or prove that the encrypted application data is HTTP. For
strict protocol enforcement, terminate TLS at the enforcement point and let the
service, reverse proxy, or stream-aware IPS reject invalid handshakes.

## Define the expected protocol before writing a rule

This example assumes an inbound IPv4 TCP service with these properties:

- TCP port `443` is the service endpoint.
- The client-to-server direction is the original connection direction.
- The first application payload is expected to begin with a TLS handshake
  record. A useful first discriminator is the two-byte prefix `0x16 0x03`.
- Cleartext HTTP requests such as `GET ` and `POST ` are protocol mismatches.

The first byte, `0x16`, is the TLS handshake content type. The next byte is the
high byte of the record version. The prefix only indicates that a packet looks
like a TLS handshake. It does not validate the record length, handshake
message, negotiated version, certificate, or cipher suite. After TLS 1.3 has
established keys, application data is encrypted, so a firewall cannot inspect
the HTTP messages inside the session without terminating TLS.

Adjust the hook for the traffic path being protected:

- Use `INPUT` for a service running on the local host.
- Use `FORWARD` for a routed or bridged service behind the firewall.
- Use `OUTPUT` for locally generated client traffic.
- Inspect both IPv4 and IPv6. The `iptables` example below is IPv4-specific;
  nftables can use an `inet` table for both families.

Place a content rule before a broad `ESTABLISHED,RELATED` accept rule. An
earlier unconditional accept prevents the packet from reaching the content
matcher. Record the existing ruleset before testing and apply the change from a
console or an out-of-band management path so a false positive does not remove
access.

## Block obvious cleartext HTTP with iptables

The `string` match searches packet bytes for a literal or hexadecimal pattern.
This example creates a small chain that logs and drops two common HTTP request
prefixes on TCP/443:

```bash
# Create this chain once. Use a different name if it already exists.
iptables -N protocol_mismatch_443

# In an existing policy, use -I INPUT <position> before a generic accept rule.
iptables -A INPUT -p tcp --dport 443 -j protocol_mismatch_443

# Log matching packets at a bounded rate, then let the next rule drop them.
iptables -A protocol_mismatch_443 \
  -m string --algo bm --hex-string '|47 45 54 20|' \
  -m limit --limit 5/min --limit-burst 10 \
  -j LOG --log-prefix 'cleartext-http-on-443: ' --log-level 4
iptables -A protocol_mismatch_443 \
  -m string --algo bm --hex-string '|47 45 54 20|' -j DROP

iptables -A protocol_mismatch_443 \
  -m string --algo bm --hex-string '|50 4f 53 54 20|' \
  -m limit --limit 5/min --limit-burst 10 \
  -j LOG --log-prefix 'cleartext-http-on-443: ' --log-level 4
iptables -A protocol_mismatch_443 \
  -m string --algo bm --hex-string '|50 4f 53 54 20|' -j DROP

# Nonmatching packets continue through the rest of INPUT.
iptables -A protocol_mismatch_443 -j RETURN
```

The hexadecimal values are ASCII `GET ` and `POST `. Add other methods such as
`HEAD `, `PUT `, `PATCH `, `DELETE `, and `OPTIONS ` when the policy needs to
cover them. A reverse-direction or forwarding rule may also need to match the
cleartext response prefix `HTTP/`.

This is a deny-list detector. It blocks the examples it recognizes, but it does
not establish that every other packet is TLS. The `string` match also operates
on the packet presented to Netfilter, not on a reassembled TCP stream. TCP
segmentation, retransmission, IPv4 or TCP options, and an attacker who chooses
different application bytes can evade or trigger the heuristic. Use counters
and a packet capture in a lab to confirm what the rule sees before relying on
it.

## Gate a flow after seeing a TLS-like payload prefix with iptables

When a deny-list is insufficient, a connection mark can remember that an
original-direction packet matched a TLS-like prefix. The following `u32`
expression walks an IPv4 packet from the IP header to the TCP header and then
to the first application-payload bytes:

```bash
tls_prefix_u32='6 & 0xFF = 6 && 4 & 0x3FFF = 0 && 0 >> 22 & 0x3C @ 0 >> 26 & 0x3C @ 0 >> 16 & 0xFFFF = 0x1603'

# Classify an unmarked client-to-server packet before INPUT is evaluated.
iptables -t mangle -A PREROUTING -p tcp --dport 443 \
  -m connmark --mark 0 \
  -m u32 --u32 "$tls_prefix_u32" \
  -j CONNMARK --set-mark 0x1

# Place this gate before any generic accept for TCP/443.
iptables -A INPUT -p tcp --dport 443 \
  -m connmark --mark 0x1 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 \
  -m conntrack --ctstate ESTABLISHED \
  -m connmark --mark 0 \
  -m limit --limit 5/min --limit-burst 10 \
  -j LOG --log-prefix 'unclassified-tcp-on-443: ' --log-level 4
iptables -A INPUT -p tcp --dport 443 \
  -m conntrack --ctstate ESTABLISHED \
  -m connmark --mark 0 -j DROP
```

The mark is stored on the conntrack entry, so later packets in the same flow
can use it. The filter fragment intentionally does not show a complete TCP
policy. Allow the required SYN, pure ACK, FIN, and RST control packets before
this gate, but do not place a broad `ESTABLISHED` accept before it. A pure TCP
control packet has no application payload and cannot be classified by the TLS
prefix rule. Handling those packets while rejecting every unmarked payload
requires careful header-length and state rules.

This pattern is still only a heuristic. It does not prove that the matching
packet was the first application payload. It can reject a valid TLS client if
the first record is split across packets or arrives in an unexpected form. It
can also accept a non-TLS flow that later contains the two matching bytes. Use
a stream-aware parser when those failure modes are unacceptable.

## Block cleartext HTTP with nftables

nftables provides a raw payload expression. `@ih,0,32` reads 32 bits at the
start of the payload after the transport header. The following `inet` table
matches common cleartext HTTP request and response prefixes on TCP/443:

```nft
table inet protocol_gate {
  chain input {
    type filter hook input priority filter; policy accept;

    tcp dport 443 @ih,0,32 {
      0x47455420,  # GET<space>
      0x504f5354,  # POST
      0x48545450   # HTTP
    } counter log prefix "cleartext-http-on-443: " drop
  }
}
```

Merge this rule into the existing input policy at a priority where an earlier
accept cannot bypass it. Use `nft -c -f /path/to/ruleset.nft` to check the
ruleset before loading it, then inspect counters with:

```bash
nft list chain inet protocol_gate input
```

The same packet-boundary, segmentation, and false-positive limitations apply
to the nftables rule. `@ih` is a raw payload expression, so it does not know
whether the bytes form a valid HTTP request or a complete TLS record.

## Gate a flow after seeing a TLS-like payload prefix with nftables

The nftables equivalent uses an early classifier chain and a conntrack mark:

```nft
table inet protocol_gate {
  chain classify_443 {
    type filter hook input priority filter - 10; policy accept;

    tcp dport 443 ct direction original ct mark 0 \
      @ih,0,16 0x1603 ct mark set 0x1
  }

  chain input_443 {
    type filter hook input priority filter; policy accept;

    # Keep narrow TCP setup and teardown rules before this gate.
    tcp dport 443 ct mark 0x1 accept
    tcp dport 443 ct direction original ct mark 0 \
      counter log prefix "unclassified-tcp-on-443: " drop
  }
}
```

`ct mark set 0x1` stores the decision on the connection, while `ct mark 0x1`
accepts later packets in that flow. The same caveat as the iptables version
applies: the control-packet rules are part of the surrounding firewall policy,
and the gate must precede any generic accept that would bypass it. For a
forwarding firewall, classify the original direction and apply the marked-flow
decision to both directions in the `FORWARD` chain.

## Verify the behavior without trusting the port number

Test both a valid TLS client and a deliberately cleartext client from an
authorized test host:

```bash
# Expected to reach the TLS service.
curl --verbose https://replace_with_test_host:443/

# Expected to be counted and dropped by the mismatch rule.
printf 'GET / HTTP/1.1\r\nHost: replace_with_test_host\r\n\r\n' \
  | nc replace_with_test_host 443
```

Review the relevant counters and kernel logs. If the TLS test fails, capture
the first client-to-server packets and check whether the TLS prefix was split
or whether another rule accepted or dropped the connection first. Repeat the
test over IPv6 and, if the policy covers HTTPS broadly, decide separately
whether UDP/443 for QUIC and HTTP/3 is allowed.

## Choose a stronger enforcement point when needed

Use a TLS-terminating reverse proxy, application listener, or stream-aware
IDS/IPS when the policy must provide any of these guarantees:

- Reassemble TCP segments before parsing.
- Validate the complete TLS handshake and negotiated parameters.
- Reject malformed or unexpected TLS records throughout the session.
- Determine whether the encrypted application protocol is HTTP.
- Apply an equivalent policy to QUIC or another encrypted transport.

Keep the host firewall as a coarse access-control layer and use the
application-aware component for protocol validation. Do not treat a matching
`0x16 0x03` prefix as authentication of the peer or of the application.

## References

- [iptables extensions manual](https://man7.org/linux/man-pages/man8/iptables-extensions.8.html), including `string`, `u32`, `connmark`, and `CONNMARK`.
- [nftables manual](https://netfilter.org/projects/nftables/manpage.html), including raw payload expressions, conntrack marks, counters, and logging.
- [nftables packet-header matching](https://wiki.nftables.org/wiki-nftables/index.php/Matching_packet_headers).
- [RFC 8446, TLS 1.3 record layer](https://www.rfc-editor.org/rfc/rfc8446.html#section-5.1).
