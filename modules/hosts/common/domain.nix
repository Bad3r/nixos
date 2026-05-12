_:
let
  body = {
    networking.domain = "local";
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
