{ config, ... }:
{
  flake.modules.nixos.lang.python.imports = with config.flake.modules.nixos.apps; [
    python
    uv
  ];
}
