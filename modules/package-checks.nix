# modules/package-checks.nix

{ lib, ... }:
{
  perSystem =
    { self', ... }:
    {
      checks = self'.packages |> lib.mapAttrs' (name: drv: lib.nameValuePair "packages/${name}" drv);
    };
}
