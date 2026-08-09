{
  writeShellApplication,
  coreutils,
  curl,
  dnsutils,
  gawk,
  gnugrep,
  gnused,
  iproute2,
  jq,
  networkmanager,
  tailscale,
  xdg-utils,
}:

writeShellApplication {
  name = "captive-portal";

  runtimeInputs = [
    coreutils
    curl
    dnsutils
    gawk
    gnugrep
    gnused
    iproute2
    jq
    networkmanager
    tailscale
    xdg-utils
  ];

  text = builtins.readFile ./captive-portal.sh;
}
