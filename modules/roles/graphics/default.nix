_: {
  flake.nixosModules.roles.graphics = {
    metadata = {
      canonicalAppStreamId = "Graphics";
      categories = [ "Graphics" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [
      ./illustration
      ./cad
      ./photography
    ];
  };
}
