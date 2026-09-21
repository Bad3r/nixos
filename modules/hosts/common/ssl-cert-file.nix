_:
let
  body = {
    # security.pki (nixpkgs ca.nix) writes this bundle and folds
    # certificateFiles into it; non-nixpkgs OpenSSL (e.g. a uv-managed
    # CPython) has no other way to find a trust store on NixOS.
    environment.sessionVariables.SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
