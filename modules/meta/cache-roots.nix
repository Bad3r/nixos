/*
  Cache Roots (issue #382)

  Aggregates the heavy custom derivations that every host switch would
  otherwise build locally into one buildable flake output,
  `packages.<system>.cache-roots`. The cache-push workflow builds this
  output on CI and pushes its closure to the binary cache, so hosts
  substitute these packages instead of rebuilding them after each
  nixpkgs bump.

  A cache hit requires the exact derivation a consumer evaluates, so
  each entry is sourced from the package set that owns it: host-enabled
  overlay packages (firefoxpwa policy injection, john patches, ...)
  come from the primary host's pkgs, and devshell-consumed packages
  come from the perSystem instance that `nix develop` uses. The lists
  are explicit allowlists because the pushed closure lands on a public
  cache: every entry must be free software whose redistribution is
  permitted. Unfree repacks (vscode, webex, kiro, ...) stay out; see
  docs/reference/binary-cache-coverage.md for the per-package
  classification and the operator runbook.
*/
{ config, lib, ... }:
let
  primaryHost = "system76";

  # tor-browser and mullvad-browser stay out: nixpkgs sets
  # allowSubstitutes = false, so hosts rebuild them whatever the cache holds.
  hostPackageNames = [
    "electron-mail"
    "firefoxpwa"
    "john"
    "planify"
    "proton-vpn"
    "searchfox-cli"
    "source-map-explorer"
    "tweakcc"
    "upscayl"
    "wappalyzer-next"
  ];

  # Modules that install a configured variant evaluate a derivation the bare
  # package-set attribute never produces, so pushing the attribute caches a
  # closure no host requests. nemo.extended wraps nemo with an explicit
  # extension list (useDefaultExtensions = false), which is what pulls
  # nemo-preview and nemo-seahorse in; neither is published by Hydra.
  # Each path must address a read-only resolved-package option with a sibling
  # `enable`. Owning modules define these options under `config` rather than as
  # an option default, so a disabled module leaves the option undefined; the
  # sibling `enable` is read here anyway, both to name the entry and host in the
  # error and to catch an owning module that grows a default later.
  hostFinalPackagePaths = {
    nemo-with-extensions = [
      "programs"
      "nemo"
      "extended"
      "finalPackage"
    ];
  };

  # Built through the perSystem nixpkgs instance (devshell surface),
  # not enabled as host apps; same redistribution constraint applies.
  perSystemPackageNames = [
    "codeburn"
    "restringer"
  ];
in
{
  perSystem =
    {
      pkgs,
      system,
      self',
      inputs',
      ...
    }:
    let
      hostPkgs = config.flake.nixosConfigurations.${primaryHost}.pkgs;
      hostConfig = config.flake.nixosConfigurations.${primaryHost}.config;

      # The pushed closure lands on a public cache, so the allowlist above is
      # only safe while every entry stays redistributable. This aborts
      # evaluation (and therefore the nix flake check that
      # modules/package-checks.nix mirrors from this output) when an entry has
      # no meta.license or carries a license that is neither free nor
      # redistributable, instead of silently publishing a license violation.
      assertFree =
        name: pkg:
        let
          licenses = lib.toList (pkg.meta.license or [ ]);
          redistributable =
            licenses != [ ]
            && lib.all (license: (license.free or false) || (license.redistributable or false)) licenses;
        in
        if redistributable then
          pkg
        else
          throw "cache-roots: ${name} is not free or redistributable; refusing to publish it to the public cache";
      entries =
        map (name: {
          inherit name;
          path = assertFree name hostPkgs.${name};
        }) hostPackageNames
        ++ lib.mapAttrsToList (
          name: optionPath:
          let
            enablePath = lib.init optionPath ++ [ "enable" ];
          in
          {
            inherit name;
            path =
              if lib.getAttrFromPath enablePath hostConfig then
                assertFree name (lib.getAttrFromPath optionPath hostConfig)
              else
                throw "cache-roots: ${name} is sourced from ${lib.concatStringsSep "." optionPath}, but that module is disabled on ${primaryHost}";
          }
        ) hostFinalPackagePaths
        ++ map (name: {
          inherit name;
          path = assertFree name self'.packages.${name};
        }) perSystemPackageNames
        ++ [
          # modules/agents/mcp.nix resolves MCP server packages from the
          # mcp-servers-nix input; hostPkgs carries same-named but different
          # context7-mcp and mcp-server-sequential-thinking derivations no
          # consumer runs.
          {
            name = "context7-mcp";
            path = assertFree "context7-mcp" inputs'.mcp-servers-nix.packages.context7-mcp;
          }
          {
            name = "mcp-server-sequential-thinking";
            path = assertFree "mcp-server-sequential-thinking" inputs'.mcp-servers-nix.packages.mcp-server-sequential-thinking;
          }
          {
            name = "codex";
            path = assertFree "codex" inputs'.llm-agents.packages.codex;
          }
        ];

      # A glob in scripts/cache-coverage-allowlist.txt accepts a permanent local
      # build; a name here publishes the package instead. Holding both leaves a
      # glob that matches nothing, which then silently absorbs the next real
      # divergence on that name at --max-count 0. Names are read back off
      # `entries` so the guard cannot fall behind the linkFarm. The failure is a
      # throw rather than a failing runCommand so that
      # `nix flake check --no-build` still catches it.
      #
      # Matched on the derivation name and pname, which is what
      # scripts/cache-coverage.sh matches globs against: the linkFarm key is
      # hand-chosen and carries no version, so the key alone would miss
      # `proton-vpn-[0-9]*` against a `proton-vpn-4.16.5` derivation, and
      # version-anchored globs are already the file's convention for wrapper
      # entries. The key is checked too. The detector never sees it, so a glob
      # spelled that way suppresses nothing, but it states the same disposition
      # this rule forbids, and it is the one candidate guaranteed to exist when
      # a path exposes neither name nor pname.
      #
      # The domain is the entries, not the closure members cache-push also
      # serves: that closure does not exist at evaluation time. A glob written
      # against a closure member (nemo-[0-9]* under nemo-with-extensions) still
      # passes here; https://github.com/Bad3r/nixos/issues/428 covers it from CI.
      allowlistGlobs =
        let
          globOf =
            line:
            let
              m = builtins.match "[[:space:]]*([^#[:space:]]+).*" line;
            in
            if m == null then null else lib.head m;
          globs = lib.filter (glob: glob != null) (
            map globOf (lib.splitString "\n" (builtins.readFile ../../scripts/cache-coverage-allowlist.txt))
          );
        in
        # This is a second parser of a format whose only other reader is
        # scripts/cache-coverage.sh. A format change this regex stops matching
        # would empty the glob list and turn the guard green rather than red,
        # so an empty parse is the failure, not a pass.
        if globs == [ ] then
          throw "cache-roots: parsed no globs out of scripts/cache-coverage-allowlist.txt; the disjointness guard would pass vacuously"
        else
          globs;

      globMatches =
        name: glob:
        builtins.match (builtins.replaceStrings [ "." "+" "*" "?" ] [ "\\." "\\+" ".*" "." ] glob) name
        != null;

      allowlistedPublished = lib.filter (
        entry:
        lib.any (candidate: lib.any (globMatches candidate) allowlistGlobs) (
          [ entry.name ]
          ++ lib.optional (entry.path ? name) entry.path.name
          ++ lib.optional (entry.path ? pname) entry.path.pname
        )
      ) entries;
    in
    {
      packages = lib.mkIf (hostPkgs.stdenv.hostPlatform.system == system) {
        cache-roots = pkgs.linkFarm "cache-roots" entries;
      };

      # Gated with packages above: the guard reads each entry's derivation, so
      # it belongs on the system that publishes them rather than resolving the
      # primary host's package set under every other perSystem instance.
      checks = lib.mkIf (hostPkgs.stdenv.hostPlatform.system == system) {
        cache-roots-allowlist-disjoint =
          if allowlistedPublished == [ ] then
            pkgs.runCommand "cache-roots-allowlist-disjoint" { } "touch $out"
          else
            throw "cache-roots: ${
              lib.concatMapStringsSep ", " (entry: entry.name) allowlistedPublished
            } is published by cache-roots.nix and also matched by a glob in scripts/cache-coverage-allowlist.txt; allowlisting and caching are mutually exclusive dispositions. Delete the glob (docs/reference/cache-coverage.md).";
      };
    };
}
