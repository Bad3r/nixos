/*
  Internal: shared Gecko-browser Multi-Account Containers
  Description: Container declarations shared across Firefox/Floorp/LibreWolf.

  Notes:
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

    Google = {
      id = 2;
      color = "orange";
      icon = "chill";
    };

    tmp = {
      id = 3;
      color = "toolbar";
      icon = "circle";
    };

    WhatsApp = {
      id = 4;
      color = "green";
      icon = "circle";
    };

    dev = {
      id = 5;
      color = "purple";
      icon = "fingerprint";
    };
  };
}
