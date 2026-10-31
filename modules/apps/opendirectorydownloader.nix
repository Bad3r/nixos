/*
  Package: opendirectorydownloader
  Description: Indexes open directories listings in 130+ supported formats
  Homepage: https://github.com/KoalaBear84/OpenDirectoryDownloader
  Documentation: https://github.com/KoalaBear84/OpenDirectoryDownloader/wiki
  Repository: https://github.com/KoalaBear84/OpenDirectoryDownloader

  Summary:
    * Saves the URLs of the indexed files.

  Options:
    -u, --url <url>: URL to scan.
    -t, --threads <number>: Number of threads (default: 5).
    -j, --json: Save a JSON file.
    -l, --upload-urls: Upload the URLs file.
    --output-file <file>: Base filename for the output files.
    --fast-scan: Skip slow checks such as HEAD requests.
*/
_:
let
  OpenDirectoryDownloaderModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.opendirectorydownloader.extended;
    in
    {
      options.programs.opendirectorydownloader.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable OpenDirectoryDownloader.";
        };

        package = lib.mkPackageOption pkgs "opendirectorydownloader" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.opendirectorydownloader = OpenDirectoryDownloaderModule;
}
