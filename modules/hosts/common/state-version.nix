_:
let
  body = {
    system.stateVersion = "26.05";
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
