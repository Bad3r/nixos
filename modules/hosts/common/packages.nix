{ lib, ... }:
let
  body =
    { pkgs, ... }:
    {
      environment.systemPackages = lib.mkAfter (
        with pkgs;
        [
          # ALSA mixer and playback tools
          alsa-utils

          # Diagnostics and stress testing utilities for crash triage
          lm_sensors
          stress-ng
          memtester
          glmark2
          hwinfo
        ]
      );
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
