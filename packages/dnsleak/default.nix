{
  lib,
  writeShellApplication,
  dnsutils,
  coreutils,
  gawk,
}:

writeShellApplication {
  name = "dnsleak";

  runtimeInputs = [
    dnsutils
    coreutils
    gawk
  ];

  text = /* bash */ ''
    echo "=== DNS Leak Test ==="
    echo ""

    # Check public IP via OpenDNS
    echo "Your public IP (via OpenDNS):"
    dig +short myip.opendns.com @resolver1.opendns.com || echo "Failed to query OpenDNS"
    echo ""

    # Show DNS servers from resolv.conf
    echo "DNS servers configured in /etc/resolv.conf:"
    if [ -f /etc/resolv.conf ]; then
      grep "^nameserver" /etc/resolv.conf | awk '{print "  " $2}'
    else
      echo "  /etc/resolv.conf not found"
    fi
    echo ""

    # Test DNS resolution
    echo "Testing DNS resolution (google.com):"
    nslookup google.com | grep -A1 "^Server:" | head -2 || echo "Failed to perform DNS lookup"
    echo ""

    echo "=== Test Complete ==="
    echo "If the DNS servers above don't match your VPN provider's DNS,"
    echo "you may have a DNS leak."
  '';

  meta = with lib; {
    description = "Simple shell utility that checks outward-facing IP and resolvers to detect DNS leaks";
    homepage = "https://github.com/vx/nixos";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.all;
  };
}
