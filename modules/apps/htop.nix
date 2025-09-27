/*
  Package: htop
  Description: Interactive process viewer and system monitor.
  Homepage: https://htop.dev/
  Documentation: https://htop.dev/
  Repository: https://github.com/htop-dev/htop

  Summary:
    * Displays real-time CPU, memory, and process metrics with color-coded bars and interaction shortcuts.
    * Allows filtering, tree views, and sending signals to processes directly from the interface.

  Options:
    --tree: Visualize processes in a hierarchical tree to inspect parent/child relationships.
    -u <user>: Filter the process list to a specific UID when launching htop.
    --sort-key <field>: Choose the metric used for ordering processes (e.g., `htop --sort-key PERCENT_CPU`).
*/

{
  flake.nixosModules.apps.htop =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.htop ];
    };
}
