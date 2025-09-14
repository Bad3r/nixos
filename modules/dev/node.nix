{ config, ... }:
let
  inherit (config.flake.lib.nixos) getApps;
  nodeImports = getApps [
    "nodejs_22"
    "nodejs_24"
    "yarn"
    "nrm"
  ];
in
{
  # Node toolchain (JS runtime + package managers) bundle
  flake.nixosModules.dev.node.imports = nodeImports;
  # Stable alias for composition without nested path lookups
  flake.nixosModules."dev-node".imports = nodeImports;
}
