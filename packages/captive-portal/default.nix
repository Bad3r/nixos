{
  lib,
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

  # mainProgram is not set here: writeTextFile derives it from the /bin/<name>
  # destination, and `nix eval ... .meta.mainProgram` already answers
  # captive-portal. platforms is linux rather than dnsleak's all, because this
  # one drives NetworkManager and iproute2.
  meta = {
    description = "Sign in to a captive portal on a host whose DNS is claimed by Tailscale";
    homepage = "https://github.com/Bad3r/nixos";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
