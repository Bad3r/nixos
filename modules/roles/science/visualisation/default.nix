_:
let
  role = {
    metadata = {
      canonicalAppStreamId = "Science";
      categories = [ "Science" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [ ];
  };
in
{
  flake.nixosModules.roles.science.visualisation = role;
}
