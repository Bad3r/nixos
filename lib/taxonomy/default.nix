{ lib }:

let
  matrix = import ./matrix.nix { inherit lib; };
  categories = lib.importJSON ./freedesktop-categories.json;
  overrides = lib.importJSON ./metadata-overrides.json;
  aliases = lib.importJSON ./alias-registry.json;
  versionInfo = import ./version.nix;

  knownSubcategories =
    let
      sublists = lib.attrValues categories.subcategories;
    in
    lib.unique (lib.concatLists sublists);

  isKnownCategory =
    cat:
    builtins.elem cat categories.roots
    || builtins.elem cat knownSubcategories
    || lib.hasPrefix "X-" cat;

  validateList =
    name: values:
    if !lib.isList values then
      [ "`${name}` must be a list of strings" ]
    else if lib.all lib.isString values then
      [ ]
    else
      [ "`${name}` contains non-string entries" ];

  validateCategories =
    name: values:
    let
      baseErrors = validateList name values;
      unknown = lib.filter (cat: !(isKnownCategory cat)) values;
    in
    baseErrors
    ++ (
      if unknown == [ ] then
        [ ]
      else
        [
          "Unknown categories in `${name}`: ${lib.concatStringsSep ", " unknown}"
        ]
    );

  validateMetadata =
    metadata:
    if metadata == null then
      {
        valid = false;
        errors = [ "metadata is null" ];
      }
    else if !builtins.isAttrs metadata then
      {
        valid = false;
        errors = [ "metadata must be an attribute set" ];
      }
    else
      let
        errors = lib.concatLists [
          (
            if !(metadata ? canonicalAppStreamId && lib.isString metadata.canonicalAppStreamId) then
              [ "`canonicalAppStreamId` must be a string" ]
            else
              [ ]
          )
          (
            if
              metadata ? canonicalAppStreamId && !(builtins.elem metadata.canonicalAppStreamId categories.roots)
            then
              [ "`canonicalAppStreamId` must be one of: ${lib.concatStringsSep ", " categories.roots}" ]
            else
              [ ]
          )
          (if !(metadata ? categories) then [ "`categories` must be defined" ] else [ ])
          (validateCategories "categories" (metadata.categories or [ ]))
          (
            if metadata ? auxiliaryCategories then
              validateCategories "auxiliaryCategories" metadata.auxiliaryCategories
            else
              [ ]
          )
          (if metadata ? secondaryTags then validateList "secondaryTags" metadata.secondaryTags else [ ])
        ];

        canonical = metadata.canonicalAppStreamId or null;
        firstCategory = lib.head (metadata.categories or [ ]);
        canonicalMismatch =
          if canonical == null || firstCategory == null then
            [ ]
          else if canonical != firstCategory then
            [ "First entry in `categories` must match `canonicalAppStreamId`" ]
          else
            [ ];
      in
      {
        valid = errors == [ ] && canonicalMismatch == [ ];
        errors = errors ++ canonicalMismatch;
      };

  lookupRootByNamespace =
    namespace: lib.findFirst (root: root.namespace == namespace) null matrix.canonicalRootsList;

in
{
  inherit matrix categories overrides aliases versionInfo;
  inherit (matrix)
    maxSegments
    vendorSegment
    canonicalRoots
    canonicalRootsList
    ;

  taxonomyVersion = versionInfo.taxonomyVersion;
  aliasHash = versionInfo.aliasHash;

  resolveOverride = pkgName: overrides.${pkgName} or null;
  inherit validateMetadata;

  inferRootFromNamespace =
    namespace:
    let
      entry = lookupRootByNamespace namespace;
    in
    if entry == null then null else entry.id;
}
