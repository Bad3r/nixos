# Regression coverage for storage-dependent writers disabled on system76.
#
# The dedicated /data volume moved to songbird. Keeping this check at the flake
# level makes the host exception fail during evaluation if either half of the
# common mirror feature or the R2 runtime is re-enabled accidentally.
{ config, lib, ... }:
let
  host = config.flake.nixosConfigurations.system76.config;
  ownerName = config.flake.lib.meta.owner.username;
  r2ServiceNames = [
    "r2-runtime-paths"
    "r2-mount-workspace"
    "r2-bisync-workspace"
    "r2-mount-fonts"
    "r2-bisync-fonts"
    "r2-mount-docs"
    "r2-bisync-docs"
    "r2-restic-backup"
  ];
  # systemd.tmpfiles.rules is a list of raw tmpfiles.d lines. Extract only the
  # path field, allowing modifier-bearing type tokens, so an argument or
  # unrelated path cannot trigger or bypass this guard. Structured settings
  # are checked separately below because NixOS renders them independently.
  tmpfilesPath =
    rule:
    let
      normalized = lib.replaceStrings [ "\t" ] [ " " ] rule;
      match = builtins.match "^ *[^ ]+ +(\"([^\"\\\\]|\\\\.)*\"|[^ ]+).*" normalized;
      token = if match == null then "" else lib.head match;
    in
    if lib.hasPrefix "\"" token && lib.hasSuffix "\"" token then
      builtins.substring 1 (builtins.stringLength token - 2) token
    else
      token;
  dataPathMatches = path: path == "/data" || lib.hasPrefix "/data/" path;
  tmpfilesPathMatchesData = rule: dataPathMatches (tmpfilesPath rule);
  tmpfilesSettingPathsFrom =
    settings: lib.concatLists (lib.mapAttrsToList (_name: paths: lib.attrNames paths) settings);
  tmpfilesSettingPaths = tmpfilesSettingPathsFrom host.systemd.tmpfiles.settings;
  tmpfilesSettingPathTestCases = [
    {
      settings = {
        "10-data" = {
          "/data/r2" = {
            d = { };
          };
        };
      };
      expected = [ "/data/r2" ];
    }
    {
      settings = {
        "10-unrelated" = {
          "/var/lib/tailscale/data" = {
            d = { };
          };
        };
      };
      expected = [ "/var/lib/tailscale/data" ];
    }
    {
      settings = {
        "10-multiple" = {
          "/data" = {
            d = { };
          };
          "/data-store" = {
            d = { };
          };
        };
      };
      expected = [
        "/data"
        "/data-store"
      ];
    }
  ];
  tmpfilesSettingPathTestFailures = lib.filter (
    test: tmpfilesSettingPathsFrom test.settings != test.expected
  ) tmpfilesSettingPathTestCases;
  tmpfilesPathTestCases = [
    {
      rule = "d /data/r2 0750 vx users - -";
      expected = true;
    }
    {
      rule = "d! /data/r2 0750 vx users - -";
      expected = true;
    }
    {
      rule = "d \"/data/r2\" 0750 vx users - -";
      expected = true;
    }
    {
      rule = "d\t/data/r2 0750 vx users - -";
      expected = true;
    }
    {
      rule = "d /var/lib/tailscale/data 0700 root root - -";
      expected = false;
    }
    {
      rule = "d /var/lib/data-store 0700 root root - -";
      expected = false;
    }
    {
      rule = "L /run/example - - - - /data/source";
      expected = false;
    }
    {
      rule = "L+ /run/example - - - - /data/source";
      expected = false;
    }
  ];
  tmpfilesPathTestFailures = lib.filter (
    test: tmpfilesPathMatchesData test.rule != test.expected
  ) tmpfilesPathTestCases;
  failures =
    lib.optional host.localMirrors.enable "localMirrors.enable is enabled"
    ++
      lib.optional host.home-manager.users.${ownerName}.programs.gitMirror.enable
        "programs.gitMirror.enable is enabled"
    ++ lib.optional (host.systemd.services ? "local-mirrors-root") "local-mirrors-root.service exists"
    ++ lib.optional (
      host.home-manager.users.${ownerName}.systemd.user.services ? "git-mirror"
    ) "user git-mirror.service exists"
    ++ lib.optional (
      host.home-manager.users.${ownerName}.systemd.user.timers ? "git-mirror"
    ) "user git-mirror.timer exists"
    ++ map (name: "${name}.service exists") (
      lib.filter (name: lib.hasAttr name host.systemd.services) r2ServiceNames
    )
    ++ map (rule: "R2 data tmpfiles rule exists: ${rule}") (
      lib.filter tmpfilesPathMatchesData host.systemd.tmpfiles.rules
    )
    ++ map (path: "R2 data tmpfiles setting exists: ${path}") (
      lib.filter dataPathMatches tmpfilesSettingPaths
    )
    ++ map (test: "tmpfiles path parser mismatch: ${test.rule}") tmpfilesPathTestFailures
    ++ map (
      test: "tmpfiles settings path extraction mismatch: ${lib.concatStringsSep ", " test.expected}"
    ) tmpfilesSettingPathTestFailures;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.system76-storage-safety =
        if failures != [ ] then
          throw ("system76-storage-safety: " + lib.concatStringsSep "; " failures)
        else
          pkgs.runCommandLocal "system76-storage-safety-ok" { } ''
            echo "ok: system76 has no /data-backed mirror or R2 writers" > $out
          '';
    };
}
