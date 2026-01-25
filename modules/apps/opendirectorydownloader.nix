/*
  Package: opendirectorydownloader
  Description: Indexes open directories listings in 130+ supported formats
  Homepage: https://github.com/KoalaBear84/OpenDirectoryDownloader
  Documentation: https://github.com/KoalaBear84/OpenDirectoryDownloader/wiki
  Repository: https://github.com/KoalaBear84/OpenDirectoryDownloader

  Summary:
    * Indexes open directories in 130+ formats including FTP, HTTP, Google Drive, Dropbox, and more.
    * Downloads directory listings with full metadata and folder structure preservation.

  Options:
    opendirectorydownloader [URL]: Scan and index the specified open directory URL.
    -u, --url [URL]: Specify the URL to scan.
    -t, --threads [NUMBER]: Number of threads to use (default: 5).
    -o, --output-file [PATH]: Save the scan results to a file.
    -j, --json: Output results in JSON format.
    --fast-scan: Enable fast scan mode (skip some checks).
    --upload-urls: Upload URLs file to file hosts.

  Example Usage:
    * `opendirectorydownloader -u https://example.com/files/` -- Scan an open directory.
    * `opendirectorydownloader -u ftp://ftp.example.com/ -t 10` -- Scan FTP with 10 threads.
    * `opendirectorydownloader -u https://example.com/files/ -j -o results.json` -- Save results as JSON.
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
