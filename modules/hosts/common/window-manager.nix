{ config, lib, ... }:
let
  i3Module = config.flake.nixosModules.i3 or null;
  body = {
    imports = lib.optional (i3Module != null) i3Module;
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
