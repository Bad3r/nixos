_:
let
  role = {
    metadata = {
      canonicalAppStreamId = "Game";
      categories = [ "Game" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [ ];
  };
in
{
  flake.nixosModules.roles.game.emulation = role;
}
