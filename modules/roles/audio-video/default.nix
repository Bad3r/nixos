_: {
  flake.nixosModules.roles."audio-video" = {
    metadata = {
      canonicalAppStreamId = "AudioVideo";
      categories = [ "AudioVideo" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [
      ./media
      ./production
      ./streaming
    ];
  };
}
