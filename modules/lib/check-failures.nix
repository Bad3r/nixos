# Failure message for the fixture-harness checks, which throw rather than fail
# a derivation so CI's `nix eval` on the check drvPath gates on them.
{ lib, ... }:
{
  flake.lib.nixos._formatCheckFailures =
    name: failures:
    "${name}: "
    + toString (lib.length failures)
    + " case(s) failed:\n  "
    + lib.concatStringsSep "\n  " failures;
}
