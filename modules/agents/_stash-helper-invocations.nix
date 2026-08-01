# Argv prefixes that must prompt before the archive-before-drop stash helper
# runs. Shared so the codex exec policy and the claude-code `bashAsk` list
# cannot drift: they gated different spellings twice in #399, once because a
# scripted edit silently matched nothing while the other file was updated.
#
# Best-effort by construction, not exhaustive. Prefix matching cannot express
# "any flags here", and `nix develop` accepts arbitrary ones (`--impure`,
# `--refresh`, `--no-write-lock-file`, an explicit `.#default`), so a spelling
# absent from this list is not gated. The flags covered are the ones this
# repository's own docs and workflows actually use.
#
# Written with builtins only so both importers can read it without arguments.
let
  nixPrefixes = [
    [
      "nix"
      "develop"
    ]
    [
      "nix"
      "--accept-flake-config"
      "develop"
    ]
  ];

  # Everything observed between `develop` and the command flag. The installable
  # is required only from a linked worktree, and the flags are accepted on
  # either side of it.
  middles = [
    [ ]
    [ "path:." ]
    [ "--accept-flake-config" ]
    [ "--offline" ]
    [
      "path:."
      "--accept-flake-config"
    ]
    [
      "--accept-flake-config"
      "path:."
    ]
    [
      "path:."
      "--offline"
    ]
    [
      "path:."
      "--accept-flake-config"
      "--offline"
    ]
    [
      "--accept-flake-config"
      "--offline"
    ]
  ];

  # `-c` and `--command` are aliases in `nix develop`.
  commandFlags = [
    "-c"
    "--command"
  ];

  wrapped = builtins.concatMap (
    prefix:
    builtins.concatMap (
      middle:
      map (
        commandFlag:
        prefix
        ++ middle
        ++ [
          commandFlag
          "prune-old-stashes"
        ]
      ) commandFlags
    ) middles
  ) nixPrefixes;
in
[
  [ "prune-old-stashes" ]
  [ "scripts/prune-old-stashes.sh" ]
  [ "./scripts/prune-old-stashes.sh" ]
]
++ wrapped
