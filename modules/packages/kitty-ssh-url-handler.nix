_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.kitty-ssh-url-handler = pkgs.callPackage ../../packages/kitty-ssh-url-handler { };
    };
}
