_:
let
  body = {
    programs.appimage = {
      enable = true;
      binfmt = true;
    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
