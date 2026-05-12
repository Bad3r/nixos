_:
let
  body = {
    boot.tmp.cleanOnBoot = true;
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
