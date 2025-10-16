_: {
  flake.nixosModules.roles.office = {
    metadata = {
      canonicalAppStreamId = "Office";
      categories = [ "Office" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [
      ./productivity
      ./planning
    ];
  };
}
