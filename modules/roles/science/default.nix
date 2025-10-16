_: {
  flake.nixosModules.roles.science = {
    metadata = {
      canonicalAppStreamId = "Science";
      categories = [ "Science" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [
      ./data
      ./visualisation
    ];
  };
}
