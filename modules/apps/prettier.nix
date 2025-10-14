/*
  Package: prettier
  Description: Opinionated code formatter supporting multiple languages (JS/TS, JSON, Markdown, etc.).
*/

{
  flake.nixosModules.apps.prettier =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.prettier ];
    };
}
