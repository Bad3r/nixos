/*
  Package: notmuch
  Description: Thread-based email index, search, and tagging system.
  Homepage: https://notmuchmail.org/
  Documentation: https://notmuchmail.org/manpages/
  Repository: https://git.notmuchmail.org/git/notmuch

  Summary:
    * Indexes a Maildir tree into a Xapian database for fast full-text search across large mail archives.
    * Tags messages and groups them into threads without moving files, leaving the Maildir layout untouched.

  Options:
    setup: Interactively create the notmuch configuration file.
    new: Index mail that arrived since the last run.
    search <terms>: List threads matching the search terms.
    tag +<tag> -<tag> -- <terms>: Add or remove tags on messages matching the search terms.
    show <terms>: Print the messages of matching threads.
*/
_:
let
  NotmuchModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.notmuch.extended;
    in
    {
      options.programs.notmuch.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable notmuch.";
        };

        package = lib.mkPackageOption pkgs "notmuch" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.notmuch = NotmuchModule;
}
