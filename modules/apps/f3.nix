/*
  Package: f3
  Description: Fight Flash Fraud toolkit for testing and repairing USB flash drives and SD cards.
  Homepage: https://fight-flash-fraud.readthedocs.io/en/stable/
  Documentation: https://fight-flash-fraud.readthedocs.io/en/stable/
  Repository: https://github.com/AltraMayor/f3

  Summary:
    * Detects counterfeit or damaged flash media by writing/verifying patterns, measuring actual capacity, and locating bad sectors.
    * Provides CLI utilities to recover partially working devices by shrinking them to their reliable capacity.

  Options:
    f3write <mountpoint>: Fill a drive with pattern files to test available capacity.
    f3read <mountpoint>: Verify pattern files written by `f3write` and report corruption.
    f3probe --destructive <device>: Perform a fast destructive test to detect true capacity and bad blocks.
    f3fix --last-sec <sector> <mountpoint>: Shrink the filesystem to the safe size determined by probe.
    f3brew: Display a summary report combining probe and fix recommendations.

  Example Usage:
    * `sudo f3write /media/usb` — Write test files across a USB drive to check its real capacity.
    * `sudo f3read /media/usb` — Validate the data written by `f3write` and identify corrupt sectors.
    * `sudo f3probe --destructive --time-ops /dev/sdc` — Run a destructive scan to estimate genuine size and performance metrics.
*/

{
  flake.nixosModules.apps.f3 =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.f3 ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.f3 ];
    };
}
