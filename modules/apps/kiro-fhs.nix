{
  # App module that installs Kiro (FHS) when imported
  flake.nixosModules.apps.kiroFhs =
    { pkgs, ... }:
    {
      # Allow unfree if required by kiro-fhs packaging
      nixpkgs.allowedUnfreePackages = [ "kiro-fhs" ];
      environment.systemPackages = [ pkgs.kiro-fhs ];
    };
}
