/*
  Package: lsof
  Description: Utility for listing open files, sockets, and devices on Unix-like systems.
  Homepage: https://github.com/lsof-org/lsof
  Documentation: https://github.com/lsof-org/lsof#readme
  Repository: https://github.com/lsof-org/lsof

  Summary:
    * Shows which processes hold file descriptors, enabling diagnosis of locks, leaks, and port conflicts.
    * Supports filtering by command, user, network endpoint, or mount point.

  Options:
    -i :<port>: Identify processes listening on or connecting to a specific TCP or UDP port.
    +D <path>: Recursively enumerate open files beneath a directory tree.
    -p <pid>: Restrict output to descriptors opened by a given process ID.
*/

/*
  Package: lsof
  Description: Utility for listing open files, sockets, and devices on Unix-like systems.
  Homepage: https://github.com/lsof-org/lsof
  Documentation: https://github.com/lsof-org/lsof#readme
  Repository: https://github.com/lsof-org/lsof

  Summary:
    * Shows which processes hold file descriptors, enabling diagnosis of locks, leaks, and port conflicts.
    * Supports filtering by command, user, network endpoint, or mount point.

  Options:
    lsof -i :<port>: Identify processes listening on or connecting to a specific port.
    lsof +D <path>: Recursively list open files beneath a directory.
    lsof -p <pid>: Display file descriptors opened by a specific process.
*/

{
  flake.nixosModules.apps.lsof =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.lsof ];
    };
}
