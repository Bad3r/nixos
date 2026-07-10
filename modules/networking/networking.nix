{
  flake.homeManagerModules.base =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        bandwhich
        dnsutils # dig, nslookup, ...
        inetutils # ping, ping6, traceroute, whois, hostname, dnsdomainname, ifconfig, logger, ...
        iproute2 # ip, ss, tc, ...
        tcpdump
        nmap # includes ncat
        socat
        curl
        wget
        ethtool
        wireshark
      ];
    };
}
