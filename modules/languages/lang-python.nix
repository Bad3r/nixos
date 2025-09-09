{ config, ... }:
{
  flake.nixosModules.lang.python.imports = with config.flake.nixosModules.apps; [
    python
    uv
  ];
}
