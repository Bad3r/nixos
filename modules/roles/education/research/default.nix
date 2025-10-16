_:
let
  role = {
    metadata = {
      canonicalAppStreamId = "Education";
      categories = [ "Education" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [ ];
  };
in
{
  flake.nixosModules.roles.education.research = role;
}
