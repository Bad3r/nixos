# modules/networking.nix

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
        environment.systemPackages = [ pkgs.impala ]; # TUI for managing wifi on Linux

        services.avahi = {
          enable = false;
          nssmdns4 = true;
          publish = {
            enable = true;
            addresses = true;
          };
        };
      };

    homeManager.base =
      { pkgs, ... }:
      {
        home.packages = with pkgs; [
          bandwhich
          #bind
          dnsutils # dig, nslookup, ...
          dnscrypt-proxy2 # TODO: Configure in nix
          nmap # includes ncat
          snicat # TLS & SNI aware netcat https://github.com/CTFd/snicat
          socat
          curl
          wget
          ethtool
          gping
          tor
          inetutils # ping, ping6, traceroute, whois, hostname, dnsdomainname, ifconfig, logger, ...
          iproute2 # ip, ss, tc, ...
          nmap
          tcpdump
          wireshark
          wireshark-cli
        ];
      };
  };
}
