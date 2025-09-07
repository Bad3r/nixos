{
  inputs,
  lib,
  ...
}:
{
  # Track flake input branches for Dendritic Pattern compliance
  flake.meta.inputBranches = lib.mapAttrs (_: input: input.sourceInfo.rev or "local") (
    lib.filterAttrs (name: _: name != "self") inputs
  );
}
