{
  inputs ? { },
  self ? null,
  lib,
  ...
}:
let
  resolvedSelf =
    if self != null then
      self
    else if inputs ? self then
      inputs.self
    else
      builtins.getFlake (toString ../..);
  modules = resolvedSelf.nixosModules or { };
in
{
  config.flake.nixosModules = lib.mkDefault modules;
}
