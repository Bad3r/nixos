_: {
  flake.homeManagerModules.passSecretServiceBackend =
    { lib, pkgs, ... }:
    {
      home.packages = lib.mkBefore [ pkgs.pass ];
      services.pass-secret-service.enable = true;
    };
}
