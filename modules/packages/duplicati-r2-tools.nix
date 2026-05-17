_: {
  perSystem =
    { pkgs, ... }:
    let
      tools = pkgs.callPackage ../../packages/duplicati-r2-tools { };
    in
    {
      packages."duplicati-r2-list" = tools.list;
      packages."duplicati-r2-extract" = tools.extract;
    };
}
