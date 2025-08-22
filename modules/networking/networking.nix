{
  flake.modules = {
    nixos.pc =
      { pkgs, ... }:
      {
        networking = {
          wireless.iwd = {
            enable = true;
            settings = {
              IPv6.Enabled = false;
              Settings.AutoConnect = true;
            };
          };
          networkmanager.wifi.backend = "iwd";
        };

        services.avahi = {
          enable = false;
          nssmdns4 = true;
          publish = {
            enable = true;
            addresses = true;
          };
        };

        # DNSCrypt
        services.dnscrypt-proxy2 = {
          enable = true;
          settings = {
            ipv6_servers = false;
            require_dnssec = true;
            sources.public-resolvers = {
              urls = [
                "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md"
                "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md"
              ];
              cache_file = "/var/lib/dnscrypt-proxy2/public-resolvers.md";
              minisign_key = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
            };
          };
        };
      };

    homeManager.base =
      { pkgs, ... }:
      {
        home.packages = with pkgs; [
          bandwhich
          dnsutils # dig, nslookup, ...
          inetutils # ping, ping6, traceroute, whois, hostname, dnsdomainname, ifconfig, logger, ...
          iproute2 # ip, ss, tc, ...
          tcpdump
          nmap # includes ncat
          snicat # TLS & SNI aware netcat https://github.com/CTFd/snicat
          socat
          curl
          wget
          ethtool
          wireshark
        ];
      };
  };
}
