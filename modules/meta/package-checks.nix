{ lib, ... }:
{
  perSystem =
    { self', ... }:
    {
      checks = lib.mapAttrs' (name: drv: lib.nameValuePair "packages/${name}" drv) self'.packages;
    };
}
