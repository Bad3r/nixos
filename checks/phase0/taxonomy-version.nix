{ lib }:

let
  taxonomy = import ../../lib/taxonomy { inherit lib; };

  aliasPairs = lib.mapAttrsToList (name: value: { inherit name value; }) taxonomy.aliases;
  sortedPairs = lib.sort (a: b: a.name < b.name) aliasPairs;
  aliasJson = builtins.toJSON sortedPairs;
  computedHash = builtins.hashString "sha256" aliasJson;

  storedVersion = taxonomy.taxonomyVersion or null;
  storedHash = taxonomy.aliasHash or null;

  errors = lib.concatLists [
    (
      if storedVersion == null || !(lib.isString storedVersion) || storedVersion == "" then
        [ "taxonomyVersion must be a non-empty string" ]
      else
        [ ]
    )
    (
      if storedHash == null || !(lib.isString storedHash) || storedHash == "" then
        [ "aliasHash must be a non-empty string" ]
      else
        [ ]
    )
    (
      if storedHash == computedHash then
        [ ]
      else
        [
          "alias registry hash mismatch (expected ${storedHash}, got ${computedHash})"
        ]
    )
  ];
in
{
  valid = errors == [ ];
  version = storedVersion;
  expectedAliasHash = storedHash;
  actualAliasHash = computedHash;
  inherit errors;
}
