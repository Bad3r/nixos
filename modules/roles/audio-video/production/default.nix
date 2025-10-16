_:
let
  role = {
    metadata = {
      canonicalAppStreamId = "AudioVideo";
      categories = [ "AudioVideo" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [ ];
  };
in
{
  flake.nixosModules.roles."audio-video".production = role;
}
