/*
  Internal: shared Gecko-browser Multi-Account Containers
  Description: Container declarations shared across Firefox/Floorp/LibreWolf.

  Notes:
    * Forcing containers.json (via `containersForce = true`) is a
      per-browser decision and lives in `_gecko-mk-profile.nix`. Floorp
      rewrites containers.json at runtime, so its profiles opt into the
      force; Firefox and LibreWolf leave it false so any UI-created
      container survives HM activation.
    * userContextId = 1 here matches the Floorp workspaces "Work" entry
      that lives in floorp.nix.
*/

_: {
  containers = {
    work = {
      id = 1;
      color = "blue";
      icon = "briefcase";
    };
  };
}
