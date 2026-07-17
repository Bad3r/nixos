/*
  Cache Roots (issue #382)

  Aggregates the heavy custom derivations that every host switch would
  otherwise build locally into one buildable flake output,
  `packages.<system>.cache-roots`. The cache-push workflow builds this
  output on CI and pushes its closure to the binary cache, so hosts
  substitute these packages instead of rebuilding them after each
  nixpkgs bump.

  A cache hit requires the exact derivation a consumer evaluates, so
  each entry is sourced from the package set that owns it: host-enabled
  overlay packages (firefoxpwa policy injection, john patches, ...)
  come from the primary host's pkgs, and devshell-consumed packages
  come from the perSystem instance that `nix develop` uses. The lists
  are explicit allowlists because the pushed closure lands on a public
  cache: every entry must be free software whose redistribution is
  permitted. Unfree repacks (vscode, webex, kiro, ...) stay out; see
  docs/reference/binary-cache-coverage.md for the per-package
  classification and the operator runbook.
*/
{ config, lib, ... }:
let
  primaryHost = "system76";

  # Free-license, redistribution-safe packages observed building locally
  # in ~/.local/state/nixos-build profiling (issue #382). Extend only
  # with packages whose full runtime closure is redistributable and whose
  # heavy derivations substitute: tor-browser and mullvad-browser are
  # excluded because nixpkgs sets allowSubstitutes = false on the main
  # derivation, so hosts rebuild them no matter what the cache holds.
  hostPackageNames = [
    "electron-mail"
    "firefoxpwa"
    "john"
    "nemo-with-extensions"
    "planify"
    "proton-vpn"
    "tweakcc"
    "upscayl"
    "wappalyzer-next"
  ];

  # Built through the perSystem nixpkgs instance (devshell surface),
  # not enabled as host apps; same redistribution constraint applies.
  perSystemPackageNames = [
    "codeburn"
    "restringer"
  ];
in
{
  perSystem =
    {
      pkgs,
      system,
      self',
      inputs',
      ...
    }:
    let
      hostPkgs = config.flake.nixosConfigurations.${primaryHost}.pkgs;
    in
    {
      packages = lib.mkIf (hostPkgs.stdenv.hostPlatform.system == system) {
        cache-roots = pkgs.linkFarm "cache-roots" (
          map (name: {
            inherit name;
            path = hostPkgs.${name};
          }) hostPackageNames
          ++ map (name: {
            inherit name;
            path = self'.packages.${name};
          }) perSystemPackageNames
          ++ [
            # modules/agents/mcp.nix resolves MCP server packages from the
            # mcp-servers-nix input; hostPkgs carries a same-named but
            # different context7-mcp derivation no consumer runs.
            {
              name = "context7-mcp";
              path = inputs'.mcp-servers-nix.packages.context7-mcp;
            }
          ]
        );
      };
    };
}
