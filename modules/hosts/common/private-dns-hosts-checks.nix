# Coverage for the secret-key collision guard in
# modules/hosts/common/private-dns-hosts.nix.
#
# tpnix declares one key and every other host declares none, so
# `collidingKeys == [ ]` is vacuously true in each host closure
# `nix flake check` evaluates. Without this file a typo in the lib.count
# predicate, or keyComponent drifting from the fold secretName applies, passes
# the whole suite while a colliding pair still drops a payload silently.
#
# This throws rather than emitting a failing derivation: CI forces each check's
# drvPath with `nix eval` and never builds checks, so only an eval-time failure
# gates it (same rationale as modules/hosts/common/checks.nix).
{ config, lib, ... }:
let
  collidingKeysOf = config.flake.lib.nixos._privateDnsCollidingKeysOf or null;
  formatCaseFailures =
    config.flake.lib.nixos._formatCheckFailures
      or (throw "modules/lib/check-failures.nix no longer exports flake.lib.nixos._formatCheckFailures");

  cases = [
    {
      name = "keys differing only by separator collide";
      keys = [
        "a_b"
        "a-b"
      ];
      expected = [
        "a_b"
        "a-b"
      ];
    }
    {
      name = "an exact duplicate collides";
      keys = [
        "a"
        "a"
      ];
      expected = [
        "a"
        "a"
      ];
    }
    {
      name = "distinct keys do not collide";
      keys = [
        "a_b"
        "c"
      ];
      expected = [ ];
    }
    {
      name = "no keys do not collide";
      keys = [ ];
      expected = [ ];
    }
    {
      # The guard names offenders, so a bystander must stay out of the message.
      name = "only the colliding pair is reported";
      keys = [
        "a_b"
        "c"
        "a-b"
      ];
      expected = [
        "a_b"
        "a-b"
      ];
    }
    {
      name = "more than two keys can share one component";
      keys = [
        "a_b"
        "a-b"
        "a_b"
      ];
      expected = [
        "a_b"
        "a-b"
        "a_b"
      ];
    }
    {
      # A lone underscore key is the shipped tpnix value: folded, never a
      # collision. A guard that compared raw keys to components would fail it.
      name = "a single underscore key is not a collision";
      keys = [ "signalx_hosts" ];
      expected = [ ];
    }
  ];

  fmt = keys: "[ ${lib.concatStringsSep " " keys} ]";

  failures = lib.concatMap (
    case:
    let
      got = collidingKeysOf case.keys;
    in
    lib.optional (got != case.expected) "${case.name}: got ${fmt got}, expected ${fmt case.expected}"
  ) cases;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.private-dns-hosts-collision-guard =
        if collidingKeysOf == null then
          throw (
            "private-dns-hosts-collision-guard: modules/hosts/common/private-dns-hosts.nix no longer "
            + "exports flake.lib.nixos._privateDnsCollidingKeysOf, so the "
            + "privateDnsHostsSecretKeys collision assertion is unverified."
          )
        else if failures != [ ] then
          throw (formatCaseFailures "private-dns-hosts-collision-guard" failures)
        else
          pkgs.runCommandLocal "private-dns-hosts-collision-guard-ok" { } ''
            echo "ok: ${toString (lib.length cases)} collision cases" > $out
          '';
    };
}
