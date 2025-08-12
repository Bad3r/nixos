# Module: package-checks.nix
# Purpose: System and user package configuration
# Namespace: flake.modules.perSystem
# Pattern: Per-system configuration - Architecture-specific packages and tools

# modules/package-checks.nix

{ lib, ... }:
{
  perSystem =
    { self', ... }:
    {
      checks = self'.packages |> lib.mapAttrs' (name: drv: lib.nameValuePair "packages/${name}" drv);
    };
}
