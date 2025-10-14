_: {
  flake.nixosModules.roles.game = {
    metadata = {
      canonicalAppStreamId = "Game";
      categories = [ "Game" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [
      ./launchers
      ./tools
      ./emulation
    ];
  };
}
