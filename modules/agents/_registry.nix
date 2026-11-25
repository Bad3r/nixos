# Validation shared by the hook, MCP, and skill registries.
{ lib }:
let
  validClients = [
    "antigravity"
    "claude"
    "codex"
  ];
in
{
  inherit validClients;

  validateAllowedFields =
    kind: context: allowedFields: attrs:
    let
      extraFields = lib.filter (field: !(lib.elem field allowedFields)) (lib.attrNames attrs);
    in
    if extraFields == [ ] then
      attrs
    else
      throw "Agent ${kind} ${context} has unknown fields: ${lib.concatStringsSep ", " extraFields}";

  validateNonEmptyString =
    kind: name: field: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "Agent ${kind} '${name}' requires non-empty string field '${field}'";

  validateClients =
    kind: name: clients:
    let
      normalizedClients = builtins.sort builtins.lessThan clients;
      unknownClients = lib.filter (client: !(lib.elem client validClients)) normalizedClients;
    in
    if !builtins.isList clients then
      throw "Agent ${kind} '${name}' requires list field 'clients'"
    else if !lib.all builtins.isString clients then
      throw "Agent ${kind} '${name}' requires all 'clients' entries to be strings"
    else if unknownClients != [ ] then
      throw ''
        Agent ${kind} '${name}' has unknown clients: ${lib.concatStringsSep ", " unknownClients}

        Valid clients: ${lib.concatStringsSep ", " validClients}
      ''
    else
      lib.unique normalizedClients;
}
