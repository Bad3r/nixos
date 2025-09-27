/*
  Package: psmisc
  Description: Utilities that use the /proc filesystem for process management tasks.
  Homepage: https://gitlab.com/psmisc/psmisc
  Documentation: https://gitlab.com/psmisc/psmisc/-/wikis/home
  Repository: https://gitlab.com/psmisc/psmisc

  Summary:
    * Supplies tools like `pstree`, `fuser`, and `killall` for diagnosing and controlling running processes.
    * Assists administrators with identifying resource conflicts, open descriptors, and process hierarchies.

  Options:
    -p: Add process IDs to the `pstree -p` output for precise inspection.
    -v: Print verbose ownership and access details via `fuser -v <path>`.
    -r <pattern>: Enable regular-expression matching when issuing `killall -r`.
*/

/*
  Package: psmisc
  Description: Utilities that use the /proc filesystem for process management tasks.
  Homepage: https://gitlab.com/psmisc/psmisc
  Documentation: https://gitlab.com/psmisc/psmisc/-/wikis/home
  Repository: https://gitlab.com/psmisc/psmisc

  Summary:
    * Supplies tools like `pstree`, `fuser`, and `killall` for diagnosing and controlling running processes.
    * Assists administrators with identifying resource conflicts, open descriptors, and process hierarchies.

  Options:
    pstree -p: Display the process tree including PIDs.
    fuser -v <path>: Show processes using a file, socket, or mount point.
    killall -r <pattern>: Terminate processes whose names match a regular expression.
*/

{
  flake.nixosModules.apps.psmisc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.psmisc ];
    };
}
