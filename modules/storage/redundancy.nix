{ lib, ... }:
{
  flake.nixosModules.base =
    { config, ... }:
    {
      options.storage.redundancy = {
        count = lib.mkOption {
          type = lib.types.int;
          default = 2;
        };
        range = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default =
            let
              inherit (config.storage.redundancy) count;
              maxIndex = lib.sub count 1;
              range = lib.range 0 maxIndex;
            in
            lib.map toString range;
        };
      };
    };

}
