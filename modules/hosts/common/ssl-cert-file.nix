_:
let
  body = {
    # Point OpenSSL consumers at the NixOS trust bundle.
    environment.sessionVariables.SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";

    # Cover callers that do not inherit the session environment.
    environment.etc."ssl/cert.pem".source = "/etc/ssl/certs/ca-certificates.crt";
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
