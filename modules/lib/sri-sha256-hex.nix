# Lix has no builtins.convertHash, and staged media declare hex digests.
{ lib, ... }:
let
  alphabet = lib.stringToCharacters "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  values = lib.listToAttrs (lib.imap0 (index: char: lib.nameValuePair char index) alphabet);
  bitsOf =
    value:
    map (shift: lib.mod (value / shift) 2) [
      32
      16
      8
      4
      2
      1
    ];
in
{
  flake.lib.nixos.sriSha256ToHex =
    sri:
    let
      digits = lib.stringToCharacters (lib.removeSuffix "=" (lib.removePrefix "sha256-" sri));
      # 43 digits carry 258 bits: the digest and two padding bits.
      bits = lib.concatMap (digit: bitsOf values.${digit}) digits;
      nibble = index: lib.foldl' (acc: bit: acc * 2 + bit) 0 (lib.sublist (4 * index) 4 bits);
    in
    assert lib.assertMsg (
      lib.hasPrefix "sha256-" sri && lib.length digits == 43
    ) "sriSha256ToHex: ${sri} is no SRI SHA-256 hash";
    lib.concatMapStrings (index: lib.toLower (lib.toHexString (nibble index))) (lib.range 0 63);
}
