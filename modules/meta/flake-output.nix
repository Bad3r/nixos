{ lib, ... }:
{
  # This option declaration allows modules to set flake.meta attributes
  # without conflicting. It's required when multiple modules contribute
  # to the flake.meta namespace.
  options.flake.meta = lib.mkOption {
    type = lib.types.anything;
    default = {};
    description = "Flake metadata that can be accessed by all modules";
  };
}