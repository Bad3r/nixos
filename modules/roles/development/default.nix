_: {
  flake.nixosModules.roles.development = {
    metadata = {
      canonicalAppStreamId = "Development";
      categories = [ "Development" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [
      ./core
      ./python
      ./go
      ./rust
      ./clojure
      ./ai
    ];
  };
}
