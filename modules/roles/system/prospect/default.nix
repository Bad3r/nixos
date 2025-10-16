_:
let
  role = {
    metadata = {
      canonicalAppStreamId = "System";
      categories = [ "System" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [ ];
  };
in
{
  flake.nixosModules.roles.system.prospect = role;
}
