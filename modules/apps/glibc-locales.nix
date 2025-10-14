{
  flake.nixosModules.apps."glibc-locales" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.glibcLocales ];
    };
}
