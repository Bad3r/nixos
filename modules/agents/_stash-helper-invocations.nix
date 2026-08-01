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
  # Every ordering of every subset, rather than a hand-written list. Listing
  # them by hand produced a partial set four times in #399, each time missing a
  # spelling that is actually typed here.
  arrangements =
    xs:
    [ [ ] ]
    ++ builtins.concatMap (
      x: map (rest: [ x ] ++ rest) (arrangements (builtins.filter (y: y != x) xs))
    ) xs;

  middles = arrangements [
    "path:."
    "--accept-flake-config"
    "--offline"
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

  # `run` and `shell` are auto-allowed subcommands too, and
  # modules/meta/prune-old-stashes-package.nix makes the helper reachable
  # through both as a flake package.
  packageInstallables = [
    ".#prune-old-stashes"
    "path:.#prune-old-stashes"
  ];

  # Flags sit between the subcommand and the installable here for the same
  # reason they do between `develop` and the command flag: nix accepts them
  # anywhere after the subcommand, and nixBases covers only the position
  # before it.
  packageMiddles = arrangements [
    "--accept-flake-config"
    "--offline"
  ];

  nixBases = [
    [ "nix" ]
    [
      "nix"
      "--accept-flake-config"
    ]
  ];

  viaPackage = builtins.concatMap (
    prefix:
    builtins.concatMap
      (
        subcommand:
        builtins.concatMap (
          middle: map (installable: prefix ++ [ subcommand ] ++ middle ++ [ installable ]) packageInstallables
        ) packageMiddles
      )
      [
        "run"
        "shell"
      ]
  ) nixBases;
in
[
  [ "prune-old-stashes" ]
  [ "scripts/prune-old-stashes.sh" ]
  [ "./scripts/prune-old-stashes.sh" ]
  # `nix build` is auto-allowed and cannot be gated by a prefix rule, since the
  # destructive step is the second command. Gate the symlink it produces for
  # modules/meta/prune-old-stashes-package.nix instead.
  [ "result/bin/prune-old-stashes" ]
  [ "./result/bin/prune-old-stashes" ]
]
++ wrapped
++ viaPackage
