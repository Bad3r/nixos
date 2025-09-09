{ lib, ... }:
{
  # Allow modules to cooperatively contribute to flake.lib.meta
  # (recognized output 'lib' avoids unknown-output warnings).
  options.flake.lib.meta = lib.mkOption {
    type = lib.types.anything;
    default = { };
    description = "Flake metadata exposed under flake.lib.meta";
  };
}
