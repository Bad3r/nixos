/*
  Package: xh
  Description: Friendly `curl`-like HTTP client inspired by HTTPie.
  Homepage: https://github.com/ducaale/xh
  Documentation: https://github.com/ducaale/xh#readme
  Repository: https://github.com/ducaale/xh

  Summary:
    * Provides a streamlined syntax for crafting HTTP requests with JSON defaults and colored output.
    * Supports session cookies, forms, streaming, and partial cURL compatibility for scripts.

  Options:
    --json: Send requests with JSON bodies and pretty-print responses (`xh --json POST …`).
    --form: Encode fields as multipart/form-data when uploading files or mixed payloads.
    --timeout <seconds>: Override the default request timeout for long-running requests.
*/

{
  flake.nixosModules.apps.xh =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xh ];
    };
}
