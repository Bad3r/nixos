_: {
  flake.nixosModules.roles.network = {
    metadata = {
      canonicalAppStreamId = "Network";
      categories = [ "Network" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [
      ./sharing
      ./tools
      ./remote-access
      ./services
      ./vendor
    ];
  };
}
