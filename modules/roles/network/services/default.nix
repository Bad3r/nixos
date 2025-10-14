_:
let
  role = {
    metadata = {
      canonicalAppStreamId = "Network";
      categories = [ "Network" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [ ];
  };
in
{
  flake.nixosModules.roles.network.services = role;
}
