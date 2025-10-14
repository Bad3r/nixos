/*
  Package: nixfmt-rfc-style
  Description: Formatter for Nix expressions following the RFC 166 style.
*/

{
  flake.nixosModules.apps."nixfmt-rfc-style" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nixfmt-rfc-style" ];
    };
}
