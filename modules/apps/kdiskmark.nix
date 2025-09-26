/*
  Package: kdiskmark
  Description: Qt-based disk benchmark inspired by CrystalDiskMark for Linux.
  Homepage: https://github.com/JonMagon/KDiskMark
  Documentation: https://github.com/JonMagon/KDiskMark#features
  Repository: https://github.com/JonMagon/KDiskMark

  Summary:
    * Measures sequential and random read/write performance using configurable test profiles and queue depths.
    * Saves HTML/PDF reports, displays graphs, and supports multiple languages with an intuitive GUI.

  Options:
    kdiskmark: Launch the graphical benchmark tool.
    Profiles menu: Select standard (SEQ1M Q8T1, RND4K Q32T16) or custom presets.
    Settings: Adjust block sizes, passes, and data sets for benchmarking.

  Example Usage:
    * `kdiskmark` — Start the GUI and run default sequential/random tests.
    * Choose “All” and click “Start” to benchmark both read and write performance.
    * Export results via “Save Report…” to archive benchmark outcomes.
*/

{
  flake.nixosModules.apps.kdiskmark =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.kdiskmark ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.kdiskmark ];
    };
}
