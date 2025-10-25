{
  perSystem =
    { pkgs, ... }:
    {
      packages."age-plugin-fido2prf" = pkgs.callPackage ../../packages/age-plugin-fido2prf { };
    };

}
