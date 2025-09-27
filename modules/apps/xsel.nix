/*
  Package: xsel
  Description: Command-line program for manipulating X11 selections and clipboard.
  Homepage: https://github.com/kfish/xsel
  Documentation: https://github.com/kfish/xsel#readme
  Repository: https://github.com/kfish/xsel

  Summary:
    * Reads from and writes to X11 primary, secondary, and clipboard selections from shell scripts.
    * Enables piping data between terminal commands and graphical clipboard managers.

  Options:
    --clipboard: Target the clipboard selection instead of PRIMARY when paired with other flags.
    --input: Read from stdin (or a redirected file) and store the data in the chosen selection.
    --clear --primary: Clear the primary selection buffer before copying new content.
*/

{
  flake.nixosModules.apps.xsel =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xsel ];
    };
}
