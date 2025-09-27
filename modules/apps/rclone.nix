/*
  Package: rclone
  Description: Command-line program to sync files and directories to cloud storage providers.
  Homepage: https://rclone.org/
  Documentation: https://rclone.org/docs/
  Repository: https://github.com/rclone/rclone

  Summary:
    * Synchronizes directories across over 70 cloud storage and S3-compatible providers with checksum verification.
    * Offers advanced features such as encryption, caching, chunked transfers, mounts, and HTTP serving.

  Options:
    --config <path>: Point rclone at an alternate configuration file containing remote definitions.
    --drive-server-side-across-configs: Enable server-side copies between Google Drive remotes when credentials permit.
    --transfers <n>: Limit the number of concurrent transfers to control bandwidth usage.
*/

{
  flake.nixosModules.apps.rclone =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.rclone ];
    };
}
