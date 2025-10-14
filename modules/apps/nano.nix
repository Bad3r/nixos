/*
  Package: nano
  Description: GNU Nano text editor for the terminal.
  Homepage: https://www.nano-editor.org/
  Documentation: https://www.nano-editor.org/dist/latest/

  Summary:
    * Lightweight terminal editor with familiar key bindings for quick edits.
    * Ships as the default fallback editor for many NixOS services.
*/

{
  flake.nixosModules.apps.nano =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nano ];
    };
}
