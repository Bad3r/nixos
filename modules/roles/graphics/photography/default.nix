_:
let
  role = {
    metadata = {
      canonicalAppStreamId = "Graphics";
      categories = [ "Graphics" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [ ];
  };
in
{
  flake.nixosModules.roles.graphics.photography = role;
}
