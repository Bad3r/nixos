/*
  Package: file-roller
  Description: Archive manager for the GNOME desktop environment.
  Homepage: https://gitlab.gnome.org/GNOME/file-roller
  Documentation: https://help.gnome.org/users/file-roller/stable/
  Repository: https://gitlab.gnome.org/GNOME/file-roller

  Summary:
    * Provides a graphical interface for creating, inspecting, and extracting archives including tar, zip, 7z, and rar formats.
    * Integrates with GNOME Files and other file managers to offer context-menu compression workflows and encrypted archives.

  Options:
    --extract-to=<dir> <archive>: Unpack the archive into a specific directory.
    --add-to=<archive> <files>: Create or append files to an archive from the command line.
    --default-dir=<dir>: Start the UI rooted in a particular directory.
    --version: Show the installed release number and exit.

  Example Usage:
    * `file-roller` — Open the GUI to browse and manipulate archives.
    * `file-roller --extract-to ~/Downloads logs.tar.xz` — Quickly unpack logs into the Downloads folder.
    * `file-roller --add-to backup.7z Documents/Reports` — Bundle reports into an encrypted-capable 7z archive.
*/

{
  flake.homeManagerModules.apps.file-roller =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.file-roller.extended;
    in
    {
      options.programs.file-roller.extended = {
        enable = lib.mkEnableOption "Archive manager for the GNOME desktop environment.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.file-roller ];
      };
    };
}
