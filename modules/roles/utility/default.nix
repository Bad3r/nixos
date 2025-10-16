_: {
  flake.nixosModules.roles.utility = {
    metadata = {
      canonicalAppStreamId = "Utility";
      categories = [ "Utility" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [
      ./cli
      ./archive
      ./monitoring
    ];
  };
}
