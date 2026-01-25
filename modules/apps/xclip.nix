/*
  Package: xclip
  Description: Command-line interface to the X11 clipboard selections.
  Homepage: https://github.com/astrand/xclip
  Documentation: https://linux.die.net/man/1/xclip
  Repository: https://github.com/astrand/xclip

  Summary:
    * Reads from and writes to X11 clipboards (PRIMARY, CLIPBOARD, SECONDARY), enabling piping data between terminal commands and graphical applications.
    * Supports selection of targets (text, image) and returns clipboard contents to stdout for scripting.

  Options:
    xclip -selection clipboard: Use the CLIPBOARD selection (Ctrl+C/Ctrl+V).
    xclip -o: Output clipboard contents to stdout.
    xclip -i: Read stdin into the clipboard (default when input redirected).
    -t <target>: Specify MIME type (e.g., text/plain, image/png).

  Example Usage:
    * `echo "Hello" | xclip -selection clipboard` -- Copy text into the clipboard.
    * `xclip -selection primary -o` -- Print the PRIMARY selection (usually mouse highlight).
    * `xclip -selection clipboard -t image/png -o > screenshot.png` -- Save an image copied to the clipboard.
*/
_:
let
  XclipModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.xclip.extended;
    in
    {
      options.programs.xclip.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable xclip.";
        };

        package = lib.mkPackageOption pkgs "xclip" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.xclip = XclipModule;
}
