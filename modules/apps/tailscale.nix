/*
  Package: tailscale
  Description: Node agent for Tailscale, a mesh VPN built on WireGuard.
  Homepage: https://tailscale.com
  Documentation: https://tailscale.com/kb/
  Repository: https://github.com/tailscale/tailscale

  Summary:
    * Installs the Tailscale client and daemon used to join tailnets and route traffic over WireGuard.
    * Enables the NixOS tailscaled service so networking state is managed declaratively.
    * Exposes common service and SSH host settings through `programs.tailscale.extended`.

  Options:
    tailscale up: Bring the node online and apply advertised routes or exit-node settings.
    tailscale status: Show peer connectivity, tunnel health, and route state.
    tailscale ssh <target>: Open an SSH session over the tailnet identity plane.
    authKeyFile: Optional file path containing a reusable auth key for non-interactive node registration.
    extraSetFlags: Additional arguments passed to `tailscale set` after daemon startup.
    interfaceName: Override the network interface name used by tailscaled (default `tailscale0`).
    sshHostAlias: Host alias written to `~/.ssh/hosts/<alias>` when tailscale is enabled.
    sshHostName: HostName used in the generated SSH match block (IP or MagicDNS name).
      Defaults to the registry host marked `primary` using that host's own
      `tailnetIp` in `flake.lib.nixos.hosts`. At most one host may be primary,
      and that host must provide a non-empty `tailnetIp` string; no primary
      leaves the default null. Hosts must switch before the generated alias changes.
*/
{ config, lib, ... }:
let
  fleetHosts = config.flake.lib.nixos.hosts or { };
  formatCaseFailures =
    config.flake.lib.nixos._formatCheckFailures
      or (throw "modules/lib/check-failures.nix no longer exports flake.lib.nixos._formatCheckFailures");
  primaryHostNamesOf =
    hosts: builtins.attrNames (lib.filterAttrs (_: host: host.primary or false) hosts);
  primaryHostNameOf =
    hosts:
    let
      names = primaryHostNamesOf hosts;
    in
    if builtins.length names == 1 then builtins.head names else null;
  duplicatePrimaryMessage =
    names:
    "flake.lib.nixos.hosts marks multiple primary hosts: ${lib.concatStringsSep ", " names}; at most one host may set primary = true";
  tailnetIpIsValid = value: lib.types.nonEmptyStr.check value;
  invalidPrimaryAddressMessage =
    name:
    "flake.lib.nixos.hosts.${name} sets primary = true without a non-empty tailnetIp string; the generated fleet SSH alias requires that address";
  primaryHasTailnetIpOf =
    hosts:
    let
      name = primaryHostNameOf hosts;
    in
    name == null || tailnetIpIsValid (hosts.${name}.tailnetIp or null);
  primaryAssertionStateOf = hosts: {
    primaryHostName = primaryHostNameOf hosts;
    atMostOnePrimary = builtins.length (primaryHostNamesOf hosts) <= 1;
    primaryHasTailnetIp = primaryHasTailnetIpOf hosts;
  };
  primaryAssertionsOf =
    hosts:
    let
      names = primaryHostNamesOf hosts;
      state = primaryAssertionStateOf hosts;
    in
    [
      {
        assertion = state.atMostOnePrimary;
        message = duplicatePrimaryMessage names;
      }
    ]
    ++ lib.optional (state.primaryHostName != null) {
      assertion = state.primaryHasTailnetIp;
      message = invalidPrimaryAddressMessage state.primaryHostName;
    };
  primaryTailnetIpOf =
    hosts:
    let
      primaryHostNames = primaryHostNamesOf hosts;
      state = primaryAssertionStateOf hosts;
    in
    if !state.atMostOnePrimary then
      throw (duplicatePrimaryMessage primaryHostNames)
    else if state.primaryHostName == null then
      null
    else if !state.primaryHasTailnetIp then
      throw (invalidPrimaryAddressMessage state.primaryHostName)
    else
      hosts.${state.primaryHostName}.tailnetIp;
  primaryTailnetIp = primaryTailnetIpOf fleetHosts;
  primaryTailnetIpTests = [
    {
      name = "no primary host";
      hosts.alpha.tailnetIp = "100.64.0.1";
      expected = null;
      expectedAssertionState = {
        primaryHostName = null;
        atMostOnePrimary = true;
        primaryHasTailnetIp = true;
      };
    }
    {
      name = "one primary host";
      hosts.alpha = {
        primary = true;
        tailnetIp = "100.64.0.1";
      };
      expected = "100.64.0.1";
      expectedAssertionState = {
        primaryHostName = "alpha";
        atMostOnePrimary = true;
        primaryHasTailnetIp = true;
      };
    }
    {
      name = "one primary host without an address";
      hosts = {
        alpha.tailnetIp = "100.64.0.1";
        beta.primary = true;
      };
      expectFailure = true;
      expectedAssertionState = {
        primaryHostName = "beta";
        atMostOnePrimary = true;
        primaryHasTailnetIp = false;
      };
    }
    {
      name = "one primary host with a null address";
      hosts.alpha = {
        primary = true;
        tailnetIp = null;
      };
      expectFailure = true;
      expectedAssertionState = {
        primaryHostName = "alpha";
        atMostOnePrimary = true;
        primaryHasTailnetIp = false;
      };
    }
    {
      name = "one primary host with an empty address";
      hosts.alpha = {
        primary = true;
        tailnetIp = "";
      };
      expectFailure = true;
      expectedAssertionState = {
        primaryHostName = "alpha";
        atMostOnePrimary = true;
        primaryHasTailnetIp = false;
      };
    }
    {
      name = "one primary host with a whitespace-only address";
      hosts.alpha = {
        primary = true;
        tailnetIp = "   ";
      };
      expectFailure = true;
      expectedAssertionState = {
        primaryHostName = "alpha";
        atMostOnePrimary = true;
        primaryHasTailnetIp = false;
      };
    }
    {
      name = "two addressed primary hosts";
      hosts = {
        alpha = {
          primary = true;
          tailnetIp = "100.64.0.1";
        };
        beta = {
          primary = true;
          tailnetIp = "100.64.0.2";
        };
      };
      expectFailure = true;
      expectedAssertionState = {
        primaryHostName = null;
        atMostOnePrimary = false;
        primaryHasTailnetIp = true;
      };
    }
    {
      name = "two primary hosts with one address";
      hosts = {
        alpha = {
          primary = true;
          tailnetIp = "100.64.0.1";
        };
        beta.primary = true;
      };
      expectFailure = true;
      expectedAssertionState = {
        primaryHostName = null;
        atMostOnePrimary = false;
        primaryHasTailnetIp = true;
      };
    }
  ];
  primaryTailnetIpTestFailures = lib.concatMap (
    test:
    let
      resolverResult = builtins.tryEval (primaryTailnetIpOf test.hosts);
      assertions = primaryAssertionsOf test.hosts;
      assertionState = primaryAssertionStateOf test.hosts;
      assertionResult = builtins.tryEval (builtins.deepSeq assertionState assertionState);
      assertionValues = map (entry: entry.assertion) assertions;
      expectedAssertionValues = [
        test.expectedAssertionState.atMostOnePrimary
      ]
      ++ lib.optional (
        test.expectedAssertionState.primaryHostName != null
      ) test.expectedAssertionState.primaryHasTailnetIp;
      assertionsResult = builtins.tryEval (
        builtins.deepSeq assertions (builtins.deepSeq assertionValues assertionValues)
      );
      resolverFailures =
        if test.expectFailure or false then
          lib.optional resolverResult.success "${test.name}: resolver evaluated to ${builtins.toJSON resolverResult.value}, expected a throw"
        else if !resolverResult.success then
          [ "${test.name}: resolver threw, expected ${builtins.toJSON test.expected}" ]
        else
          lib.optional (resolverResult.value != test.expected)
            "${test.name}: resolver got ${builtins.toJSON resolverResult.value}, expected ${builtins.toJSON test.expected}";
      assertionFailures =
        if !assertionResult.success then
          [ "${test.name}: assertion state threw, expected ${builtins.toJSON test.expectedAssertionState}" ]
        else
          lib.optional (assertionResult.value != test.expectedAssertionState)
            "${test.name}: assertion state got ${builtins.toJSON assertionResult.value}, expected ${builtins.toJSON test.expectedAssertionState}";
      assertionsFailures =
        if !assertionsResult.success then
          [ "${test.name}: emitted assertions threw during full evaluation" ]
        else
          lib.optional (assertionsResult.value != expectedAssertionValues)
            "${test.name}: assertion values got ${builtins.toJSON assertionsResult.value}, expected ${builtins.toJSON expectedAssertionValues}";
    in
    resolverFailures ++ assertionFailures ++ assertionsFailures
  ) primaryTailnetIpTests;
  TailscaleModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tailscale.extended;
    in
    {
      options.programs.tailscale.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable tailscale.";
        };

        package = lib.mkPackageOption pkgs "tailscale" { };

        authKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Optional path to a Tailscale auth key file used by tailscaled.";
        };

        extraSetFlags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional flags passed to `tailscale set` by the NixOS module.";
        };

        interfaceName = lib.mkOption {
          type = lib.types.str;
          default = "tailscale0";
          description = "Network interface name used for the tailscale tunnel.";
        };

        sshHostAlias = lib.mkOption {
          type = lib.types.str;
          default = "tailscale";
          description = "SSH host alias generated under `~/.ssh/hosts/` for tailscale access.";
        };

        sshHostName = lib.mkOption {
          type = lib.types.nullOr lib.types.nonEmptyStr;
          default = primaryTailnetIp;
          description = ''
            SSH HostName for the tailscale host entry (IP or MagicDNS name).
            Defaults to the flake.lib.nixos.hosts entry marked primary using that
            host's own tailnetIp. At most one host may be primary, and that host
            must provide a non-empty tailnetIp string. No primary leaves this null
            and skips the generated ~/.ssh/hosts alias.
          '';
        };
      };

      config = lib.mkMerge [
        {
          assertions = primaryAssertionsOf fleetHosts;
        }
        (lib.mkIf cfg.enable {
          environment.systemPackages = [ cfg.package ];

          services.tailscale = lib.mkMerge [
            {
              enable = true;
              inherit (cfg) package interfaceName extraSetFlags;
            }
            (lib.mkIf (cfg.authKeyFile != null) {
              inherit (cfg) authKeyFile;
            })
          ];
        })
      ];
    };
in
{
  flake.nixosModules.apps.tailscale = TailscaleModule;

  perSystem =
    { pkgs, ... }:
    {
      checks."apps/tailscale-primary-host" =
        assert builtins.deepSeq primaryTailnetIp true;
        if primaryTailnetIpTestFailures != [ ] then
          throw (formatCaseFailures "apps/tailscale-primary-host" primaryTailnetIpTestFailures)
        else
          pkgs.runCommandLocal "tailscale-primary-host-ok" { } ''
            echo "ok: ${toString (builtins.length primaryTailnetIpTests)} primary-host cases" > $out
          '';
    };
}
