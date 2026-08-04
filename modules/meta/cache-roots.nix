/*
  Cache Roots (issue #382)

  Aggregates the heavy derivations that a host switch would otherwise build
  locally into one buildable flake output, `packages.<system>.cache-roots`.
  The cache-push workflow builds this output on CI and pushes its closure to
  the binary cache, so hosts substitute these packages instead of rebuilding
  them after each nixpkgs bump.

  A cache hit requires the exact derivation a consumer evaluates, so each
  entry is sourced where that consumer resolves it: host apps come from the
  option each host installs, and devshell-consumed packages come from the
  perSystem instance that `nix develop` uses. Every registered host on the
  building system contributes its own entries (issue #423), so an app a
  sibling host enables and the primary does not still reaches the cache, and
  a host that turns an app off contributes nothing for it.

  The cache is operator-private in use, so unfree packages are published
  alongside free ones; see docs/reference/binary-cache-coverage.md for the
  per-package inventory and the operator runbook.
*/
{ config, lib, ... }:
let
  # Apps published for every host that enables them, gated on
  # programs.<name>.extended.enable and resolved through
  # programs.<name>.extended.package. A name enabled on no host is a throw
  # below rather than a silently absent entry.
  #
  # Each of these modules installs its own extended.package, so that option
  # and not the bare package-set attribute is what a host evaluates. A host
  # overriding it keeps extended.enable = true, so reading the attribute
  # instead would leave the gate green while publishing a derivation nobody
  # builds, and the symptom would be a cache miss rather than an error.
  #
  # tor-browser and mullvad-browser stay out: nixpkgs sets
  # allowSubstitutes = false on the derivation that carries the build, so
  # hosts rebuild them whatever the cache holds. Entries whose outer wrapper
  # sets the same flag over a substitutable closure (electron-mail, kiro-fhs,
  # upscayl, vscode-fhs) belong here, because the closure underneath is the
  # expensive half.
  #
  # Names are the attributes hosts install, which is not always the attribute
  # that shares the app's common name: vscode-fhs and ventoy-full are what
  # modules/apps/ enables, and the bare vscode and ventoy attributes are
  # derivations no host consumes.
  hostPackageNames = [
    "burpsuite"
    "charles"
    "discord"
    "dropbox"
    "electron-mail"
    "firefoxpwa"
    "google-chrome"
    "john"
    "kiro-fhs"
    "nomachine-client"
    "obsidian"
    "p7zip-rar"
    "planify"
    "proton-vpn"
    "searchfox-cli"
    "source-map-explorer"
    "tweakcc"
    "upscayl"
    "ventoy-full"
    "veracrypt"
    "vscode-fhs"
    "wappalyzer-next"
    "webex"
  ];

  nvidiaLoaded = hostConfig: lib.elem "nvidia" hostConfig.services.xserver.videoDrivers;

  # Packages the bare package-set attribute never produces, or that never
  # reach environment.systemPackages at all. Each entry names the attribute
  # path holding the resolved package and the condition under which the host
  # actually installs it. A path may reach past the option into the value it
  # holds, for derivations that hang off a package rather than being one.
  #
  # The condition is explicit rather than derived from the option path
  # because these options do not share one shape. nemo.extended.finalPackage
  # is assigned inside `config = lib.mkIf cfg.enable` and is undefined when
  # the module is off, so its sibling `enable` is the real signal.
  # hardware.nvidia.package and programs.steam.package carry upstream defaults
  # and stay defined on hosts that never install them, so no sibling
  # extended.enable is readable there; services.xserver.videoDrivers and the
  # upstream programs.steam.enable are what actually install them.
  hostOptionPackages = {
    nemo-with-extensions = {
      path = [
        "programs"
        "nemo"
        "extended"
        "finalPackage"
      ];
      installed = hostConfig: hostConfig.programs.nemo.extended.enable;
    };
    nvidia-x11 = {
      path = [
        "hardware"
        "nvidia"
        "package"
      ];
      installed = nvidiaLoaded;
    };
    # Two derivations hanging off hardware.nvidia.package rather than outputs
    # of it, so linking every output does not reach them. `mod` is the kernel
    # module built against boot.kernelPackages, which upstream puts in
    # boot.extraModulePackages whenever hardware.nvidia.open is not true, and
    # is the expensive half of the driver. `settings` is nvidia-settings,
    # added to environment.systemPackages under hardware.nvidia.nvidiaSettings.
    nvidia-kernel-modules = {
      path = [
        "hardware"
        "nvidia"
        "package"
        "mod"
      ];
      installed = hostConfig: nvidiaLoaded hostConfig && hostConfig.hardware.nvidia.open != true;
    };
    nvidia-settings = {
      path = [
        "hardware"
        "nvidia"
        "package"
        "settings"
      ];
      installed = hostConfig: nvidiaLoaded hostConfig && hostConfig.hardware.nvidia.nvidiaSettings;
    };
    # modules/apps/steam.nix installs nothing itself: it sets
    # programs.steam.enable with extraCompatPackages and extraPackages, and
    # upstream's programs.steam.package carries an `apply` that re-overrides
    # the FHS env with both lists. The applied value is what upstream puts in
    # environment.systemPackages, and proton-ge-bin, dwarfs, fuse-overlayfs,
    # and protonup-rs live inside it; pkgs.steam is a different derivation
    # missing exactly the part that costs a switch.
    steam = {
      path = [
        "programs"
        "steam"
        "package"
      ];
      installed = hostConfig: hostConfig.programs.steam.enable;
    };
  };

  # Built through the perSystem nixpkgs instance (devshell surface),
  # not enabled as host apps.
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
      # Only hosts this system can build for. A host on another platform
      # belongs to that platform's cache-roots, not this one.
      hosts = lib.filterAttrs (
        _: nixos: nixos.pkgs.stdenv.hostPlatform.system == system
      ) config.flake.nixosConfigurations;

      appEnabled =
        hostConfig: name: ((hostConfig.programs.${name} or { }).extended or { }).enable or false;

      hostEntries =
        hostName: nixos:
        let
          hostConfig = nixos.config;
        in
        map (name: {
          key = "${hostName}/${name}";
          pkgName = name;
          path = hostConfig.programs.${name}.extended.package;
        }) (lib.filter (appEnabled hostConfig) hostPackageNames)
        ++ lib.mapAttrsToList (name: entry: {
          key = "${hostName}/${name}";
          pkgName = name;
          path = lib.getAttrFromPath entry.path hostConfig;
        }) (lib.filterAttrs (_: entry: entry.installed hostConfig) hostOptionPackages);

      hostConfigs = map (nixos: nixos.config) (lib.attrValues hosts);

      # A name no host enables publishes nothing, so the list would carry it
      # forever while the cache stayed unchanged. That is the failure mode
      # this whole file exists to prevent, so it aborts rather than thins the
      # output silently. Renaming an app or turning it off on the last host
      # that had it lands here.
      unusedAppNames = lib.filter (
        name: !(lib.any (hostConfig: appEnabled hostConfig name) hostConfigs)
      ) hostPackageNames;

      unusedOptionNames = lib.attrNames (
        lib.filterAttrs (
          _: entry: !(lib.any (hostConfig: entry.installed hostConfig) hostConfigs)
        ) hostOptionPackages
      );

      unused = unusedAppNames ++ unusedOptionNames;

      entries =
        if unused != [ ] then
          throw "cache-roots: ${lib.concatStringsSep ", " unused} is listed in cache-roots.nix but enabled on no host that builds for ${system}; publishing it is a no-op. Drop the name or enable the app."
        else
          lib.concatLists (lib.mapAttrsToList hostEntries hosts)
          ++ map (name: {
            key = name;
            pkgName = name;
            path = self'.packages.${name};
          }) perSystemPackageNames
          ++ [
            # modules/agents/mcp.nix resolves MCP server packages from the
            # mcp-servers-nix input; host package sets carry same-named but
            # different context7-mcp and mcp-server-sequential-thinking
            # derivations no consumer runs.
            {
              key = "context7-mcp";
              pkgName = "context7-mcp";
              path = inputs'.mcp-servers-nix.packages.context7-mcp;
            }
            {
              key = "mcp-server-sequential-thinking";
              pkgName = "mcp-server-sequential-thinking";
              path = inputs'.mcp-servers-nix.packages.mcp-server-sequential-thinking;
            }
            {
              key = "codex";
              pkgName = "codex";
              path = inputs'.llm-agents.packages.codex;
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
      # scripts/cache-coverage.sh matches globs against: the entry name is
      # hand-chosen and carries no version, so it alone would miss
      # `proton-vpn-[0-9]*` against a `proton-vpn-4.16.5` derivation, and
      # version-anchored globs are already the file's convention for wrapper
      # entries. The entry name is checked too. The detector never sees it, so a
      # glob spelled that way suppresses nothing, but it states the same
      # disposition this rule forbids, and it is the one candidate guaranteed to
      # exist when a path exposes neither name nor pname. The host-qualified
      # linkFarm key is not checked, because no glob is written that way.
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
          [ entry.pkgName ]
          ++ lib.optional (entry.path ? name) entry.path.name
          ++ lib.optional (entry.path ? pname) entry.path.pname
        )
      ) entries;

      # Hosts share most apps, so the same derivation arrives under several
      # host-qualified keys. linkFarm rejects duplicate keys, not duplicate
      # paths, and the keys already differ; the closure counts each path once.
      #
      # Every output is linked, not just the default one. cache-push walks the
      # closure of this linkFarm, and a multi-output derivation's outPath does
      # not reach its siblings, so those outputs would be built on CI and then
      # dropped. nvidia-x11 alone splits into out, lib32, bin, modsrc, and
      # firmware.
      linkFarmEntries = lib.concatMap (
        entry:
        map (output: {
          name = "${entry.key}/${output}";
          path = entry.path.${output};
        }) (entry.path.outputs or [ "out" ])
      ) entries;

      buildsHere = hosts != { };
    in
    {
      packages = lib.mkIf buildsHere {
        cache-roots = pkgs.linkFarm "cache-roots" linkFarmEntries;
      };

      # Gated with packages above: the guard reads each entry's derivation, so
      # it belongs on the system that publishes them rather than resolving every
      # host's package set under every other perSystem instance.
      checks = lib.mkIf buildsHere {
        cache-roots-allowlist-disjoint =
          if allowlistedPublished == [ ] then
            pkgs.runCommand "cache-roots-allowlist-disjoint" { } "touch $out"
          else
            throw "cache-roots: ${
              lib.concatMapStringsSep ", " (entry: entry.pkgName) allowlistedPublished
            } is published by cache-roots.nix and also matched by a glob in scripts/cache-coverage-allowlist.txt; allowlisting and caching are mutually exclusive dispositions. Delete the glob (docs/reference/cache-coverage.md).";
      };
    };
}
