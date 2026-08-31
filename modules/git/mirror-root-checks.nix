# Coverage for the mount derivation in modules/git/mirror-root.nix.
#
# enclosingMountOf decides whether local-mirrors-root.service carries an
# ordering and a ConditionPathIsMountPoint at all, so a wrong answer provisions
# the mirror root on the root filesystem and every downstream guard then passes
# against it. A host closure may exercise either branch, so the check below
# covers both an enclosing data mount and a root-backed mirror root.
#
# This throws rather than emitting a failing derivation: CI forces each check's
# drvPath with `nix eval` and never builds checks, so only an eval-time failure
# gates it (same rationale as modules/hosts/common/firewall-checks.nix).
{ config, lib, ... }:
let
  enclosingMountOf = config.flake.lib.nixos._localMirrorsEnclosingMount or null;

  fs = mountPoint: { inherit mountPoint; };

  cases = [
    {
      name = "mount keyed by its own path";
      root = "/data/git";
      fileSystems = {
        "/" = fs "/";
        "/boot" = fs "/boot";
        "/data" = fs "/data";
      };
      expected = "/data";
    }
    {
      # The key carries no path at all; only mountPoint does.
      name = "mount keyed by a name, path only in mountPoint";
      root = "/data/git";
      fileSystems = {
        "/" = fs "/";
        data = fs "/data";
      };
      expected = "/data";
    }
    {
      name = "host mounts the mirror root itself";
      root = "/data/git";
      fileSystems = {
        "/" = fs "/";
        "/data" = fs "/data";
        "/data/git" = fs "/data/git";
      };
      expected = "/data/git";
    }
    {
      # No enclosing mount means provision unconditionally, which is correct
      # only because there is no volume that could be absent.
      name = "mirrors on the root filesystem";
      root = "/data/git";
      fileSystems."/" = fs "/";
      expected = null;
    }
    {
      # A shallower match would gate on a mount that can be present while the
      # one actually holding the root is not.
      name = "deepest candidate wins";
      root = "/data/git";
      fileSystems = {
        "/data" = fs "/data";
        "/data/git" = fs "/data/git";
      };
      expected = "/data/git";
    }
    {
      # Nothing forbids two fileSystems entries naming the same mount point, and
      # the fold's tie-break is strict, so a duplicate must not displace it.
      name = "two keys naming the same mount point";
      root = "/data/git";
      fileSystems = {
        "/" = fs "/";
        "/data" = fs "/data";
        data-alias = fs "/data";
      };
      expected = "/data";
    }
    {
      # Prefix matching is on path segments: /databases must not gate /data/git.
      name = "sibling sharing a name prefix does not match";
      root = "/data/git";
      fileSystems = {
        "/" = fs "/";
        "/databases" = fs "/databases";
      };
      expected = null;
    }
  ];

  fmt = value: if value == null then "null" else value;

  failures = lib.concatMap (
    case:
    let
      got = enclosingMountOf case.root case.fileSystems;
    in
    lib.optional (got != case.expected) "${case.name}: got ${fmt got}, expected ${fmt case.expected}"
  ) cases;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.local-mirrors-enclosing-mount =
        if enclosingMountOf == null then
          throw (
            "local-mirrors-enclosing-mount: modules/git/mirror-root.nix no longer exports "
            + "flake.lib.nixos._localMirrorsEnclosingMount, so the mount gate on "
            + "local-mirrors-root.service is unverified."
          )
        else if failures != [ ] then
          throw (
            "local-mirrors-enclosing-mount: "
            + toString (lib.length failures)
            + " case(s) failed:\n  "
            + lib.concatStringsSep "\n  " failures
          )
        else
          pkgs.runCommandLocal "local-mirrors-enclosing-mount-ok" { } ''
            echo "ok: ${toString (lib.length cases)} mount-derivation cases" > $out
          '';
    };
}
