_:
let
  body = {
    # Non-nixpkgs OpenSSL (uv-managed CPython) finds no trust store on NixOS without it.
    environment.sessionVariables.SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
