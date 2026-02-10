/*
  Package: xxd
  Description: Standalone hex dump and reverse hex dump utility.
  Homepage: https://github.com/xyproto/tinyxxd
  Documentation: https://github.com/xyproto/tinyxxd/blob/main/tinyxxd.1
  Repository: https://github.com/xyproto/tinyxxd

  Summary:
    * Creates hexadecimal, binary, and C include dumps from files or standard input.
    * Reverses hex dumps back into binary form for round-trip editing and patching.

  Options:
    -b: Switch to binary digit dump (eight 1s and 0s per octet) instead of hex.
    -c cols: Format output with cols octets per line (default 16).
    -i: Output in C include file style with a named static array definition.
    -p: Output in PostScript continuous plain hexdump style.
    -r: Reverse operation, convert hex dump back into binary.
    -R when: Colorize output (always, auto, or never).
    -e: Switch to little-endian hexdump, grouping bytes as words.
    -s [+][-]seek: Start at seek bytes into the input.
    -l len: Stop after len octets.
    -u: Use uppercase hex letters instead of lowercase.

  Notes:
    * Package is tinyxxd, a drop-in replacement for the xxd utility bundled with ViM.
*/
_:
let
  XxdModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.xxd.extended;
    in
    {
      options.programs.xxd.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable xxd.";
        };

        package = lib.mkPackageOption pkgs "tinyxxd" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.xxd = XxdModule;
}
