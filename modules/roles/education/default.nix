_: {
  flake.nixosModules.roles.education = {
    metadata = {
      canonicalAppStreamId = "Education";
      categories = [ "Education" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [
      ./research
      ./learning-tools
    ];
  };
}
