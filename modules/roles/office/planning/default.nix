_:
let
  role = {
    metadata = {
      canonicalAppStreamId = "Office";
      categories = [ "Office" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [ ];
  };
in
{
  flake.nixosModules.roles.office.planning = role;
}
