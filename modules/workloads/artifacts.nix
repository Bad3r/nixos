# Built on demand into an out-link; no flake check evaluates legacyPackages
# and no host closure references them.
{ lib, ... }:
{
  perSystem =
    { config, ... }:
    {
      options.workloads.artifacts = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.raw;
        default = { };
        description = "Workload images and media, exposed as `legacyPackages.<system>.workloads.<name>`.";
      };

      config.legacyPackages.workloads = config.workloads.artifacts;
    };
}
