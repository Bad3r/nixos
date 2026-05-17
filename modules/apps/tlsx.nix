/*
  Package: tlsx
  Description: TLS data gathering and analysis toolkit.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/projectdiscovery/tlsx

  Summary:
    * Collects TLS certificate, handshake, cipher, and fingerprint data from hosts.
    * Supports CT log streaming, TLS version and cipher enumeration, and JSONL output for pipelines.

  Options:
    -u, -host <value>: Target host to scan.
    -l, -list <file>: Target list to scan.
    -p, -port <ports>: Target ports to connect to.
    -san / -cn / -so: Display subject alternative names, common names, or organization names.
    -tv, -tls-version: Display the negotiated TLS version.
    -ve, -version-enum: Enumerate supported TLS versions.
    -ce, -cipher-enum: Enumerate supported ciphers.
    -j, -json: Display JSON output.
    -silent: Display silent output.
*/
_:
let
  TlsxModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tlsx.extended;
    in
    {
      options.programs.tlsx.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable tlsx.";
        };

        package = lib.mkPackageOption pkgs "tlsx" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.tlsx = TlsxModule;
}
