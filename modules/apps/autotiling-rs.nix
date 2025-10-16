/*
  Package: autotiling-rs
  Description: Sway and i3 helper that alternates horizontal and vertical splits automatically.
  Homepage: https://github.com/ammgws/autotiling-rs
  Documentation: https://github.com/ammgws/autotiling-rs#readme
  Repository: https://github.com/ammgws/autotiling-rs

  Summary:
    * Listens to sway and i3 window focus events and toggles the next split orientation to keep layouts balanced.
    * Accepts workspace filters so you can confine autotiling to tiling workspaces while leaving others manual.

  Options:
    -w, --workspace <N> [<N>...]: Restrict autotiling to the given workspace numbers.
    -h, --help: Print usage information and exit.
    -V, --version: Show the installed autotiling-rs version.

  Example Usage:
    * `autotiling-rs` — Start the daemon to alternate horizontal and vertical splits globally.
    * `autotiling-rs --workspace 1 3 5` — Only adjust layouts on workspaces 1, 3, and 5.
    * `exec_always autotiling-rs` — Add to your sway config so autotiling launches on login.
*/

{
  flake.nixosModules.apps."autotiling-rs" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."autotiling-rs" ];
    };
}
