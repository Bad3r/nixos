/*
  Internal: shared Gecko-browser Multi-Account Containers
  Description: Container declarations shared across Firefox/Floorp/LibreWolf.

  Notes:
    * containersForce = true mirrors Floorp's runtime behavior of rewriting
      containers.json on every launch; forcing the file means the declarative
      list always wins.
    * userContextId = 1 here matches the Floorp workspaces "Work" entry that
      lives in floorp.nix.
*/

_: {
  containersForce = true;
  containers = {
    work = {
      id = 1;
      color = "blue";
      icon = "briefcase";
    };
  };
}
