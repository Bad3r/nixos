/*
  Package: tor
  Description: Anonymizing overlay network daemon that routes TCP traffic through volunteer relays.
  Homepage: https://www.torproject.org/
  Documentation: https://torproject.gitlab.io/tor-manual/tor/
  Repository: https://github.com/torproject/tor

  Summary:
    * Provides onion-routing circuits that hide client network location by relaying connections through volunteer-operated nodes.
    * Can operate as a client, relay, bridge, or onion service host via torrc configuration to support censorship circumvention and self-hosted services.

  Options:
    --torrc-file FILE: Load a specific torrc configuration file instead of the default path.
    --allow-missing-torrc: Start even if the specified torrc file cannot be found.
    --defaults-torrc FILE: Append default configuration directives from an additional torrc template.
    --list-fingerprint [TYPE]: Print the relay identity fingerprint (optionally for a given key type) and exit.
    --verify-config: Validate configuration files and exit without starting the daemon.
*/
_:
let
  TorModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tor.extended;
    in
    {
      options.programs.tor.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable tor.";
        };

        package = lib.mkPackageOption pkgs "tor" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.tor = TorModule;
}
