{ lib, ... }:
{
  perSystem =
    {
      config,
      system,
      ...
    }:
    lib.mkIf (system == "x86_64-linux") {
      formatter = config.treefmt.build.wrapper;
    };
}
