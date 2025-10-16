{ lib }:
let
  taxonomy = import ../../lib/taxonomy { inherit lib; };
  aliases = taxonomy.aliases or { };
  inherit (taxonomy) matrix;
  roots = matrix.canonicalRootsList;
  aliasHash = taxonomy.aliasHash or "";
  sentinelPlaceholder = "pending-phase0-baseline";

  vendorPrefix = "vendor";

  rootForCanonical =
    canonical:
    lib.findFirst (
      root: canonical == root.namespace || lib.hasPrefix (root.namespace + ".") canonical
    ) null roots;

  toSegments = path: lib.splitString "." path;

  joinSegments = segments: if segments == [ ] then "" else lib.concatStringsSep "." segments;

  remainderSegmentsFor =
    root: canonical:
    let
      namespaceSegments = toSegments root.namespace;
      targetSegments = toSegments canonical;
      nsLen = builtins.length namespaceSegments;
    in
    if builtins.length targetSegments < nsLen then [ ] else lib.lists.drop nsLen targetSegments;

  validateAlias =
    aliasEntry:
    let
      aliasName = aliasEntry.name;
      canonical = aliasEntry.value;
      canonicalIsString = builtins.isString canonical;
      aliasPrefixErrors =
        if lib.hasPrefix "roles." aliasName then
          [ ]
        else
          [ "Alias '${aliasName}' must live under the roles.* namespace" ];
      canonicalTypeErrors =
        if canonicalIsString then
          [ ]
        else
          [
            "Alias '${aliasName}' must resolve to a string canonical path (got ${builtins.typeOf canonical})"
          ];
      canonicalPrefixErrors =
        if canonicalIsString && lib.hasPrefix "roles." canonical then
          [ ]
        else if canonicalIsString then
          [ "Canonical target for '${aliasName}' must live under roles.* (got ${canonical})" ]
        else
          [ ];
      canonicalSameAsAliasErrors =
        if canonicalIsString && aliasName == canonical then
          [ "Alias '${aliasName}' must not point to itself" ]
        else
          [ ];
      root = if canonicalIsString then rootForCanonical canonical else null;
      rootErrors =
        if canonicalIsString && root == null then
          [ "Canonical target '${canonical}' for alias '${aliasName}' does not map to a known taxonomy root" ]
        else
          [ ];
      remainderSegments = if root == null then [ ] else remainderSegmentsFor root canonical;
      remainder = joinSegments remainderSegments;
      reserved = if root == null then [ ] else (root.reservedSubroles or [ ]);
      allowedSubroles = if root == null then [ ] else root.subroles ++ reserved;
      allowedList =
        if allowedSubroles == [ ] then "(none documented)" else lib.concatStringsSep ", " allowedSubroles;
      vendorErrors =
        if root == null || remainderSegments == [ ] || builtins.head remainderSegments != vendorPrefix then
          [ ]
        else
          let
            allowVendor = root.allowVendor or false;
            vendorHasName = builtins.length remainderSegments >= 2;
            allowError =
              if allowVendor then
                [ ]
              else
                [
                  "Alias '${aliasName}' points to vendor namespace '${canonical}' but root '${root.namespace}' does not allow vendor subroles"
                ];
            nameError =
              if vendorHasName then
                [ ]
              else
                [
                  "Alias '${aliasName}' must specify a vendor name (found '${canonical}')"
                ];
          in
          allowError ++ nameError;
      subroleErrors =
        if root == null || remainderSegments == [ ] || builtins.head remainderSegments == vendorPrefix then
          [ ]
        else if lib.elem remainder allowedSubroles then
          [ ]
        else
          [
            "Alias '${aliasName}' points to unknown subrole '${canonical}'. Expected one of: ${allowedList}"
          ];
    in
    lib.concatLists [
      aliasPrefixErrors
      canonicalTypeErrors
      canonicalPrefixErrors
      canonicalSameAsAliasErrors
      rootErrors
      vendorErrors
      subroleErrors
    ];

  aliasEntries = lib.attrsToList aliases;
  sentinelErrors =
    if aliasHash == sentinelPlaceholder then
      [
        "Phase 0 sentinel: alias registry still reports placeholder hash '${sentinelPlaceholder}'. Regenerate the alias registry and update lib/taxonomy/version.nix before enabling this check."
      ]
    else
      [ ];
  errors = lib.concatMap validateAlias aliasEntries ++ sentinelErrors;
in
{
  valid = errors == [ ];
  inherit errors aliases;
}
