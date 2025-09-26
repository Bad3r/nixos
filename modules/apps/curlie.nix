/*
  Package: curlie
  Description: HTTPie-style frontend that wraps curl while keeping its feature set.
  Homepage: https://rs.github.io/curlie/
  Documentation: https://rs.github.io/curlie/
  Repository: https://github.com/rs/curlie

  Summary:
    * Provides HTTPie-like syntax and formatting on top of curl's request engine.
    * Streams colorized, pretty JSON output without buffering interactive responses.

  Options:
    --curl: Print the composed curl command instead of executing it.
    --pretty: Force pretty-printed JSON output even when stdout is not a TTY.
    --form: Treat key=value pairs as multipart/form-data fields when composing requests.
    -h CATEGORY: Display curl's grouped help pages (for example `-h all`).
*/

{
  flake.nixosModules.apps.curlie =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.curlie ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.curlie ];
    };
}
