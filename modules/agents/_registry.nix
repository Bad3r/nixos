# Validation shared by the hook, MCP, and skill registries.
{ lib }:
{
  validClients = [
    "claude"
    "codex"
  ];

  validateAllowedFields =
    kind: context: allowedFields: attrs:
    let
      extraFields = lib.filter (field: !(lib.elem field allowedFields)) (lib.attrNames attrs);
    in
    if extraFields == [ ] then
      attrs
    else
      throw "Agent ${kind} ${context} has unknown fields: ${lib.concatStringsSep ", " extraFields}";
}
