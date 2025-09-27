/*
  Package: nix-tree
  Description: Interactive CLI for exploring Nix derivation dependency trees.
  Homepage: https://github.com/utdemir/nix-tree
  Documentation: https://github.com/utdemir/nix-tree#readme
  Repository: https://github.com/utdemir/nix-tree

  Summary:
    * Visualizes closure structure, outputs, and references for packages stored in the Nix store.
    * Provides TUI navigation, search, and export options to inspect build dependencies efficiently.

  Options:
    --derivation <path>: Render the dependency tree rooted at the given derivation.
    --gc-roots <path>: Highlight whether nodes are protected by garbage-collector roots.
    --include-outputs: Include runtime outputs alongside build-time dependencies.
*/

{
  flake.nixosModules.apps."nix-tree" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nix-tree" ];
    };
}
