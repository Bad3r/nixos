_: {
  flake.nixosModules.roles.system = {
    metadata = {
      canonicalAppStreamId = "System";
      categories = [ "System" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = [
      ./base
      ./display/x11
      ./storage
      ./security
      ./nixos
      ./virtualization
      ./prospect
      ./vendor
    ];
  };
}
