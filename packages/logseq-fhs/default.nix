{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  fetchYarnDeps,
  prefetchYarnDeps,
  writeShellScriptBin,
  copyDesktopItems,
  clojure,
  git,
  cacert,
  nodejs_22,
  yarnBuildHook,
  yarnConfigHook,
  removeReferencesTo,
  makeWrapper,
  makeDesktopItem,
  python3,
  pkg-config,
  gnumake,
  gcc,
  pkgs,
  electron,
  buildFHSEnv,
  nodePackages_latest,
  runCommand,
  ...
}:
{
  logseqSrc,
  version,
  electronPackage ? electron,
}:
let
  gitDeps = import ./git-deps.nix { inherit fetchFromGitHub; };
  yarnLocks = import ./yarn-deps.nix;

  placeholderMap = {
    "@bb_tasks_src@" = gitDeps.bb_tasks_src;
    "@bb_tasks_db_src@" = gitDeps.bb_tasks_db_src;
    "@rum_src@" = gitDeps.rum_src;
    "@datascript_src@" = gitDeps.datascript_src;
    "@cljs_time_src@" = gitDeps.cljs_time_src;
    "@cljc_fsrs_src@" = gitDeps.cljc_fsrs_src;
    "@cljs_http_missionary_src@" = gitDeps.cljs_http_missionary_src;
    "@clj_fractional_indexing_src@" = gitDeps.clj_fractional_indexing_src;
    "@wally_src@" = gitDeps.wally_src;
    "@nbb_test_runner_src@" = gitDeps.nbb_test_runner_src;
    "@cognitect_test_runner_src@" = gitDeps.cognitect_test_runner_src;
    "@electron_node_gyp_src@" = gitDeps.electron_node_gyp_src;
    "@electron_forge_maker_appimage_src@" = gitDeps.electron_forge_maker_appimage_src;
  };

  localGitPaths = {
    "@electron_node_gyp_src@" = ".nix-cache/git/electron-node-gyp";
    "@electron_forge_maker_appimage_src@" = ".nix-cache/git/electron-forge-maker-appimage";
  };

  electronNodeGypRev = "06b29aafb7708acef8b3669835c8a7857ebc92d2";
  electronNodeGypArchive = "node-gyp-${electronNodeGypRev}";
  electronForgeMakerAppimageRev = "4bf4d4eb5925f72945841bd2fa7148322bc44189";

  nodeGypTarball = runCommand "logseq-${version}-${electronNodeGypArchive}-tgz" { } ''
    mkdir -p "$out"
    tar --directory ${gitDeps.electron_node_gyp_src} \
      --transform='s,^\.,package,' \
      -czf "$out/${electronNodeGypArchive}.tgz" .
  '';

  nodeGypTarballPath = "${nodeGypTarball}/${electronNodeGypArchive}.tgz";

  nodeGypUnpacked = runCommand "logseq-${version}-${electronNodeGypArchive}-unpacked" { } ''
    mkdir -p "$out"
    tar -xzf ${nodeGypTarballPath} -C "$out"
    mv "$out/package" "$out/node-gyp"
  '';

  nodeGypDirPath = "${nodeGypUnpacked}/node-gyp";

  dugiteNativeTarball = fetchurl {
    url = "https://github.com/desktop/dugite-native/releases/download/v2.43.4/dugite-native-v2.43.4-f5c5df6-ubuntu-x64.tar.gz";
    sha256 = "0yqvvjf6fak5bvrfl8c6pjj9bh3i0czvx238rwf88my7z8drcrqf";
  };

  lmdbDarwinArm64 = fetchurl {
    url = "https://registry.yarnpkg.com/@lmdb/lmdb-darwin-arm64/-/lmdb-darwin-arm64-2.5.2.tgz";
    sha256 = "1wdr3xrx2pnjz2r78fs77hi753l05i59cymh6xmx74wxrv71fzfn";
  };

  lmdbDarwinX64 = fetchurl {
    url = "https://registry.yarnpkg.com/@lmdb/lmdb-darwin-x64/-/lmdb-darwin-x64-2.5.2.tgz";
    sha256 = "0ypr5d0sfj95bwac2gqpsb43smp3c40fvh9bn760sl44g5h0m684";
  };

  extractBuilderArtifact =
    {
      name,
      url,
      sha256,
      outputDir,
      finalName ? null,
    }:
    let
      src = fetchurl { inherit url sha256; };
    in
    runCommand "logseq-${version}-${name}-cache"
      {
        nativeBuildInputs = [
          pkgs.p7zip
          pkgs.gnutar
        ];
      }
      ''
          set -euo pipefail
          work="$(mktemp -d)"
          7z x ${src} -o"$work"
          shopt -s nullglob
        for archive in "$work"/*.tar "$work"/*.tar.gz; do
          if [ -e "$archive" ]; then
            tar -xf "$archive" -C "$work"
            rm "$archive"
          fi
        done
        shopt -u nullglob
        if [ ! -e "$work/${outputDir}" ]; then
          mkdir -p "$work/${outputDir}"
          shopt -s dotglob
          for entry in "$work"/*; do
            if [ "$entry" = "$work/${outputDir}" ]; then
              continue
            fi
            mv "$entry" "$work/${outputDir}/"
          done
          shopt -u dotglob
        fi
          sourcePath="$work/${outputDir}"
          if [ ! -e "$sourcePath" ]; then
            echo "error: expected ${outputDir} in extracted ${name}" >&2
            ls -R "$work" >&2
            exit 1
          fi
          mkdir -p "$out"
          destName="${if finalName == null then "" else finalName}";
          if [ -z "$destName" ]; then
            destName="$(basename "$sourcePath")"
          fi
          if [ -d "$sourcePath" ]; then
            cp -R "$sourcePath" "$out/$destName"
          else
            mkdir -p "$out/$destName"
            cp "$sourcePath" "$out/$destName/$(basename "$sourcePath")"
          fi
          rm -rf "$work"
      '';

  builderAppImage = extractBuilderArtifact {
    name = "appimage";
    url = "https://github.com/electron-userland/electron-builder-binaries/releases/download/appimage-12.0.1/appimage-12.0.1.7z";
    sha256 = "1i4frdpdqqnazqv5c12qqz0aqcyapmzpl8x55ijw87hxizmzfbyi";
    outputDir = "appimage-12.0.1";
  };

  builderSnapAmd64 = extractBuilderArtifact {
    name = "snap-template-electron-4.0-2-amd64";
    url = "https://github.com/electron-userland/electron-builder-binaries/releases/download/snap-template-4.0-2/snap-template-electron-4.0-2-amd64.tar.7z";
    sha256 = "0vwys52frdckz1s76b3b7y9qqc9qj6mjs71b0zq0db34jghb8fjy";
    outputDir = "snap-template-electron-4.0-2-amd64";
  };

  builderSnapArmhf = extractBuilderArtifact {
    name = "snap-template-electron-4.0-1-armhf";
    url = "https://github.com/electron-userland/electron-builder-binaries/releases/download/snap-template-4.0-1/snap-template-electron-4.0-1-armhf.tar.7z";
    sha256 = "0sxywf868a9jx4ifq7xn00xjh6p00nfqkw0r62y47q7l0klm6xbg";
    outputDir = "snap-template-electron-4.0-1-armhf";
  };

  builderFpm = extractBuilderArtifact {
    name = "fpm-1.9.3-2.3.1-linux-x86_64";
    url = "https://github.com/electron-userland/electron-builder-binaries/releases/download/fpm-1.9.3-2.3.1-linux-x86_64/fpm-1.9.3-2.3.1-linux-x86_64.7z";
    sha256 = "1zxsvflxpgrmz8yyqdydfc58n9xikaks5810hqhj7r3qz3v989q8";
    outputDir = "fpm-1.9.3-2.3.1-linux-x86_64";
  };

  builderZstd = extractBuilderArtifact {
    name = "zstd-v1.5.5-linux-x64";
    url = "https://github.com/electron-userland/electron-builder-binaries/releases/download/zstd-1.5.5/zstd-v1.5.5-linux-x64.7z";
    sha256 = "1rkgdqhqw0pi0cfkmai5qsrb6f6d4jnysyiniibb3kd3vdi3nbvr";
    outputDir = "zstd";
    finalName = "zstd-1.5.5-linux-x64";
  };

  electronBuilderCache = runCommand "logseq-${version}-electron-builder-cache" { } ''
    set -euo pipefail
    mkdir -p "$out/appimage" "$out/snap" "$out/fpm" "$out/zstd"
    cp -R ${builderAppImage}/appimage-12.0.1 "$out/appimage/"
    cp -R ${builderSnapAmd64}/snap-template-electron-4.0-2-amd64 "$out/snap/"
    cp -R ${builderSnapArmhf}/snap-template-electron-4.0-1-armhf "$out/snap/"
    cp -R ${builderFpm}/fpm-1.9.3-2.3.1-linux-x86_64 "$out/fpm/"
    cp -R ${builderZstd}/zstd-1.5.5-linux-x64 "$out/zstd/"
  '';

  addNodeGyp =
    cache:
    let
      baseName = builtins.baseNameOf (toString cache);
    in
    runCommand "${baseName}-with-node-gyp" { } ''
      mkdir -p "$out"
      cp -r ${cache}/. "$out/"
      chmod u+w "$out"
      cp ${nodeGypTarballPath} "$out/"
    '';

  placeholderFiles = [
    "bb.edn"
    "deps.edn"
    "clj-e2e/deps.edn"
    "deps/cli/bb.edn"
    "deps/cli/nbb.edn"
    "deps/common/bb.edn"
    "deps/common/deps.edn"
    "deps/common/nbb.edn"
    "deps/db/bb.edn"
    "deps/db/deps.edn"
    "deps/db/nbb.edn"
    "deps/graph-parser/bb.edn"
    "deps/graph-parser/deps.edn"
    "deps/graph-parser/nbb.edn"
    "deps/outliner/bb.edn"
    "deps/outliner/deps.edn"
    "deps/outliner/nbb.edn"
    "deps/publishing/bb.edn"
    "deps/publishing/nbb.edn"
    "deps/shui/deps.edn"
  ];

  inherit (lib) concatStringsSep escapeShellArg getExe;

  substituteArgs = concatStringsSep " " (
    map (
      placeholder:
      "--replace-warn ${escapeShellArg placeholder} ${escapeShellArg placeholderMap.${placeholder}}"
    ) (builtins.attrNames placeholderMap)
  );

  placeholderFileList = concatStringsSep " " (map escapeShellArg placeholderFiles);

  placeholderSubstitutionScript = ''
    for file in ${placeholderFileList}; do
      if [ ! -f "$file" ]; then
        echo "error: placeholder file $file is missing" >&2
        exit 1
      fi
      substituteInPlace "$file" ${substituteArgs}
    done

    if grep -R -E '@[A-Za-z0-9_]+@' --include='*.edn' --include='*.bb' --include='*.clj*' .; then
      echo "error: unresolved placeholder markers remain" >&2
      exit 1
    fi
  '';

  rewriteYarnLocksScript = ''
    find . -name yarn.lock | while IFS= read -r lock; do
      if grep -q 'github.com/electron/node-gyp' "$lock"; then
        substituteInPlace "$lock" \
          --replace-warn "git+https://github.com/electron/node-gyp.git#${electronNodeGypRev}" "file:${
            localGitPaths."@electron_node_gyp_src@"
          }" \
          --replace-warn "https://github.com/electron/node-gyp#${electronNodeGypRev}" "file:${
            localGitPaths."@electron_node_gyp_src@"
          }"
      fi
      if grep -q 'github.com/logseq/electron-forge-maker-appimage' "$lock"; then
        substituteInPlace "$lock" \
          --replace-warn '"electron-forge-maker-appimage@https://github.com/logseq/electron-forge-maker-appimage.git"' "\"electron-forge-maker-appimage@file:${
            localGitPaths."@electron_forge_maker_appimage_src@"
          }\"" \
          --replace-warn "git+https://github.com/logseq/electron-forge-maker-appimage.git#${electronForgeMakerAppimageRev}" "file:${
            localGitPaths."@electron_forge_maker_appimage_src@"
          }" \
          --replace-warn "https://github.com/logseq/electron-forge-maker-appimage.git#${electronForgeMakerAppimageRev}" "file:${
            localGitPaths."@electron_forge_maker_appimage_src@"
          }"
      fi
      if grep -q 'electron-forge-maker-appimage@file:@electron_forge_maker_appimage_src@' "$lock"; then
        substituteInPlace "$lock" \
          --replace-warn '"electron-forge-maker-appimage@file:@electron_forge_maker_appimage_src@"' "\"electron-forge-maker-appimage@file:${
            localGitPaths."@electron_forge_maker_appimage_src@"
          }\"" \
          --replace-warn 'resolved "file:@electron_forge_maker_appimage_src@"' "resolved \"file:${
            localGitPaths."@electron_forge_maker_appimage_src@"
          }\""
      fi
    done
  '';

  patchedSrc = runCommand "logseq-${version}-patched" { } ''
    set -euo pipefail
    cp -r ${logseqSrc} $out
    chmod -R u+w $out
    cd "$out"
    patch -p1 < ${./main-placeholder.patch}
    ${placeholderSubstitutionScript}
    ${rewriteYarnLocksScript}
  '';

  baseYarnCaches = lib.mapAttrs' (
    name: info:
    let
      lockPath =
        if info ? lockFile then
          if info ? src then "${info.src}/${info.lockFile}" else "${patchedSrc}/${info.lockFile}"
        else
          "${patchedSrc}/yarn.lock";
      srcPath =
        let
          root = info.sourceRoot or ".";
        in
        if root == "." then patchedSrc else "${patchedSrc}/${root}";
      infoWithPaths = info // {
        lockFile = lockPath;
        yarnLock = lockPath;
        postBuild = (info.postBuild or "") + ''
          rm -f yarn.lock
        '';
      };
      info' = infoWithPaths;
      info'' = info' // {
        src = srcPath;
        sourceRoot = ".";
      };
    in
    lib.nameValuePair name (
      fetchYarnDeps (
        {
          pname = "logseq";
          inherit version;
          name = "logseq-${version}-yarn-${name}";
          patches = [ ];
        }
        // info''
      )
    )
  ) yarnLocks;

  resourcesOfflineCache = stdenv.mkDerivation {
    name = "logseq-${version}-yarn-resources";
    src = ./resources-workspace;
    dontInstall = true;

    nativeBuildInputs = [
      prefetchYarnDeps
      cacert
    ];
    GIT_SSL_CAINFO = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    NODE_EXTRA_CA_CERTS = "${cacert}/etc/ssl/certs/ca-bundle.crt";

    buildPhase = ''
      runHook preBuild
      lockFile="$PWD/yarn.lock"
      substituteInPlace package.json --replace '@electron_forge_maker_appimage_src@' "${gitDeps.electron_forge_maker_appimage_src}"
      substituteInPlace yarn.lock --replace '@electron_forge_maker_appimage_src@' "${gitDeps.electron_forge_maker_appimage_src}"
      mkdir -p $out
      (cd $out; prefetch-yarn-deps "$lockFile" --builder)
      cp ${nodeGypTarballPath} "$out/"
      rm -f $out/yarn.lock
      runHook postBuild
    '';

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "1601n3n8934fvrv9lj3649bvxbri4c122482rp433ldvphf8hmz9";
  };

  yarnOfflineCaches =
    (
      baseYarnCaches
      // {
        root = addNodeGyp baseYarnCaches.root;
      }
    )
    // {
      resources = resourcesOfflineCache;
    };

  # Clojure wrapper that reuses the precomputed Maven cache
  clojureWithCache =
    repository:
    writeShellScriptBin "clojure" ''
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"
      export GIT_SSL_CAINFO=${cacert}/etc/ssl/certs/ca-bundle.crt
      exec ${lib.getExe' clojure "clojure"} -Sdeps '{:mvn/local-repo "'"${repository}"'"}' "$@"
    '';

  nodeGypOptional = writeShellScriptBin "node-gyp-build-optional-packages" ''
    if command -v node-gyp-build >/dev/null 2>&1; then
      exec node-gyp-build "$@"
    else
      echo "warning: node-gyp-build not available; skipping optional native build" >&2
      exit 0
    fi
  '';

  staticPackageJson = builtins.fromJSON (builtins.readFile ./resources-workspace/package.json);
  electronVersion =
    let
      declared = staticPackageJson.devDependencies.electron or null;
    in
    if declared == null then lib.getVersion electronPackage else declared;

  electronArchiveFile = "electron-v${electronVersion}-linux-x64.zip";
  electronArchiveHashes = {
    "37.2.6" = "08xsk32pg21lw5d971svls6hp96psvgf86gk9acb8pxmvjnyvciv";
  };
  electronZipHash =
    electronArchiveHashes.${electronVersion}
      or (throw "Missing electron hash for version ${electronVersion}");
  electronZipPath = fetchurl {
    url = "https://github.com/electron/electron/releases/download/v${electronVersion}/${electronArchiveFile}";
    sha256 = electronZipHash;
  };
  electronShasumPath = fetchurl {
    url = "https://github.com/electron/electron/releases/download/v${electronVersion}/SHASUMS256.txt";
    sha256 = "1w3aj9m1lbybwwchj5bm20lhplik32qssbgyva7zff1l77vqs9gh";
  };

  electronUnpacked =
    runCommand "electron-${electronVersion}-unpacked" { nativeBuildInputs = [ pkgs.unzip ]; }
      ''
        mkdir -p "$out"
        cd "$out"
        unzip ${electronZipPath}
      '';
  electronDist = electronUnpacked;
  electronBinary = "${electronDist}/electron";

  runtimeDeps =
    pkgs:
    with pkgs;
    [
      alsa-lib
      at-spi2-atk
      at-spi2-core
      atk
      cairo
      cups
      dbus
      dejavu_fonts
      expat
      fontconfig
      freetype
      gdk-pixbuf
      glib
      gtk3
      harfbuzz
      krb5
      libappindicator-gtk3
      libdrm
      libnotify
      libpulseaudio
      libsecret
      libuuid
      libxkbcommon
      nspr
      nss
      pango
      pipewire
      udev
      xdg-desktop-portal
      xdg-user-dirs
      xdg-utils
      zlib
    ]
    ++ (with pkgs.xorg; [
      libX11
      libXScrnSaver
      libXcomposite
      libXcursor
      libXdamage
      libXext
      libXfixes
      libXi
      libXrandr
      libXrender
      libXtst
      libxcb
      libXau
      libXdmcp
    ])
    ++ (with pkgs; [
      libglvnd
      libgbm
      mesa
    ]);

  logseqUnwrapped = stdenv.mkDerivation (finalAttrs: {
    pname = "logseq-unwrapped";
    inherit version;
    src = logseqSrc;

    patches = [ ./main-placeholder.patch ];

    nativeBuildInputs =
      let
        clojureWrapper = clojureWithCache finalAttrs.mavenRepo;
        fakeGit = writeShellScriptBin "git" ''
          if [ "$1" = "rev-parse" ]; then
            echo "${finalAttrs.src.rev or version}"
            exit 0
          fi
          exec ${getExe git} "$@"
        '';
      in
      [
        clojureWrapper
        copyDesktopItems
        fakeGit
        makeWrapper
        nodejs_22
        nodePackages_latest.node-gyp-build
        nodeGypOptional
        python3
        pkg-config
        gnumake
        gcc
        git
        cacert
        yarnBuildHook
        yarnConfigHook
        removeReferencesTo
        pkgs.p7zip
      ];

    buildInputs = [ ];

    dontYarnInstallDeps = true;
    env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

    postPatch = ''
      set -euo pipefail

      ${placeholderSubstitutionScript}

      ${rewriteYarnLocksScript}

      mkdir -p $(dirname ${localGitPaths."@electron_node_gyp_src@"})
      rm -rf ${localGitPaths."@electron_node_gyp_src@"}
      cp -R ${nodeGypDirPath} ${localGitPaths."@electron_node_gyp_src@"}
      chmod -R u+w ${localGitPaths."@electron_node_gyp_src@"}

      mkdir -p $(dirname ${localGitPaths."@electron_forge_maker_appimage_src@"})
      rm -rf ${localGitPaths."@electron_forge_maker_appimage_src@"}
      cp -R ${gitDeps.electron_forge_maker_appimage_src} ${
        localGitPaths."@electron_forge_maker_appimage_src@"
      }
      chmod -R u+w ${localGitPaths."@electron_forge_maker_appimage_src@"}
    '';

    mavenRepo = stdenv.mkDerivation {
      name = "logseq-${version}-maven";
      inherit (finalAttrs) src patches postPatch;
      nativeBuildInputs = [
        clojure
        git
        cacert
      ];
      buildPhase = ''
        runHook preBuild
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        export GIT_SSL_CAINFO=${cacert}/etc/ssl/certs/ca-bundle.crt
        mkdir -p "$out"
        ${lib.getExe' clojure "clojure"} -Sdeps '{:mvn/local-repo "'"$out"'"}' -P -M:cljs
        runHook postBuild
      '';
      installPhase = "true";
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = "sha256-OE5GOxj1JP2YnIP9o16L/jOCgfcx17oBU5Xm2CYVuO8=";
    };

    postConfigure = ''
      prepare_cache() {
        local dest="$1"
        local src="$2"
        rm -rf "$dest"
        mkdir -p "$dest"
        cp -Rp "$src"/. "$dest/"
        chmod -R u+w "$dest"
      }

      register_cache() {
        local var_name="$1"
        local src="$2"
        local suffix="$3"
        local dest="$TMPDIR/yarn-cache-$suffix"
        prepare_cache "$dest" "$src"
        printf -v "$var_name" '%s' "$dest"
        export "$var_name"
        yarnOfflineCache="$dest" yarnConfigHook
      }

      register_cache LOGSEQ_YARN_CACHE_ROOT ${yarnOfflineCaches.root} root

      pushd scripts
      register_cache LOGSEQ_YARN_CACHE_SCRIPTS ${yarnOfflineCaches.scripts} scripts
      popd

      pushd libs
      register_cache LOGSEQ_YARN_CACHE_LIBS ${yarnOfflineCaches.libs} libs
      popd

      pushd deps/common
      register_cache LOGSEQ_YARN_CACHE_DEPS_COMMON ${yarnOfflineCaches.deps_common} deps-common
      popd

      pushd deps/db
      register_cache LOGSEQ_YARN_CACHE_DEPS_DB ${yarnOfflineCaches.deps_db} deps-db
      popd

      pushd deps/graph-parser
      register_cache LOGSEQ_YARN_CACHE_DEPS_GRAPH_PARSER ${yarnOfflineCaches.deps_graph_parser} deps-graph-parser
      popd

      pushd deps/outliner
      register_cache LOGSEQ_YARN_CACHE_DEPS_OUTLINER ${yarnOfflineCaches.deps_outliner} deps-outliner
      popd

      pushd deps/publishing
      register_cache LOGSEQ_YARN_CACHE_DEPS_PUBLISHING ${yarnOfflineCaches.deps_publishing} deps-publishing
      popd

      pushd deps/cli
      register_cache LOGSEQ_YARN_CACHE_DEPS_CLI ${yarnOfflineCaches.deps_cli} deps-cli
      popd

      pushd packages/amplify
      register_cache LOGSEQ_YARN_CACHE_PACKAGES_AMPLIFY ${yarnOfflineCaches.packages_amplify} packages-amplify
      popd

      pushd packages/tldraw
      register_cache LOGSEQ_YARN_CACHE_PACKAGES_TLDRAW ${yarnOfflineCaches.packages_tldraw} packages-tldraw
      popd

      pushd packages/ui
      register_cache LOGSEQ_YARN_CACHE_PACKAGES_UI ${yarnOfflineCaches.packages_ui} packages-ui
      popd

    '';

    yarnBuildScript = "release-electron";

    buildPhase = ''
                        runHook preBuild
                        export HOME="$TMPDIR/home"
                        mkdir -p "$HOME/.cache" "$TMPDIR/yarn" "$TMPDIR/electron-cache"
                        export YARN_CACHE_FOLDER="$TMPDIR/yarn"
                        export ELECTRON_CACHE="$TMPDIR/electron-cache"
                        export ELECTRON_BUILDER_CACHE="$TMPDIR/electron-builder"
                        export LOGSEQ_SENTRY_DSN=""
                        export LOGSEQ_POSTHOG_TOKEN=""
                        export ENABLE_FILE_SYNC_PRODUCTION=true
                        export ENABLE_PLUGINS=true
                        export CI=1
                        export npm_config_optional=false
                        export npm_config_nodedir=${nodejs_22.dev}
                        export LOGSEQ_YARN_CACHE_RESOURCES="$TMPDIR/yarn-cache-resources"
                        rm -rf "$LOGSEQ_YARN_CACHE_RESOURCES"
                        mkdir -p "$LOGSEQ_YARN_CACHE_RESOURCES"
                        cp -Rp ${resourcesOfflineCache}/. "$LOGSEQ_YARN_CACHE_RESOURCES/"
                        chmod -R u+w "$LOGSEQ_YARN_CACHE_RESOURCES"
                        export DUGITE_CACHE_DIR="$LOGSEQ_YARN_CACHE_RESOURCES"
                        cp ${dugiteNativeTarball} "$LOGSEQ_YARN_CACHE_RESOURCES/dugite-native-v2.43.4-f5c5df6-ubuntu-x64.tar.gz"
                        cp ${lmdbDarwinArm64} "$LOGSEQ_YARN_CACHE_RESOURCES/_lmdb_lmdb_darwin_arm64___lmdb_darwin_arm64_2.5.2.tgz"
                        cp ${lmdbDarwinX64} "$LOGSEQ_YARN_CACHE_RESOURCES/_lmdb_lmdb_darwin_x64___lmdb_darwin_x64_2.5.2.tgz"

                        yarn config set yarn-offline-mirror "$LOGSEQ_YARN_CACHE_ROOT" --cwd "$PWD"
                        yarn install --offline --frozen-lockfile --ignore-scripts
                        patchShebangs node_modules

                        yarn --cwd libs config set yarn-offline-mirror "$LOGSEQ_YARN_CACHE_LIBS"
                        yarn --cwd libs install --offline --frozen-lockfile --ignore-optional --production=false --ignore-scripts
                        patchShebangs libs/node_modules
                        PATH="$PWD/libs/node_modules/.bin:$PATH" yarn --cwd libs run build

                        yarn --cwd packages/amplify config set yarn-offline-mirror "$LOGSEQ_YARN_CACHE_PACKAGES_AMPLIFY"
                        yarn --cwd packages/amplify install --offline --frozen-lockfile --ignore-optional --production=false --ignore-scripts
                        patchShebangs packages/amplify/node_modules
                        (PATH="$PWD/packages/amplify/node_modules/.bin:$PATH" yarn --cwd packages/amplify run build:amplify)

                        yarn --cwd packages/tldraw config set yarn-offline-mirror "$LOGSEQ_YARN_CACHE_PACKAGES_TLDRAW"
                        yarn --cwd packages/tldraw install --offline --frozen-lockfile --ignore-optional --production=false --ignore-scripts
                        patchShebangs packages/tldraw/node_modules
                        if [ -d packages/tldraw/apps/tldraw-logseq/node_modules ]; then
                          patchShebangs packages/tldraw/apps/tldraw-logseq/node_modules
                        fi
                        (PATH="$PWD/packages/tldraw/node_modules/.bin:$PATH" yarn --cwd packages/tldraw run build)

                        yarn --cwd packages/ui config set yarn-offline-mirror "$LOGSEQ_YARN_CACHE_PACKAGES_UI"
                        yarn --cwd packages/ui install --offline --frozen-lockfile --ignore-optional --production=false --ignore-scripts
                        patchShebangs packages/ui/node_modules
                        (PATH="$PWD/packages/ui/node_modules/.bin:$PATH" yarn --cwd packages/ui run build:ui)

                        yarn run gulp build
                        yarn run cljs:release-electron
                        yarn run webpack-app-build

                        cp ${./resources-workspace/yarn.lock} static/yarn.lock
                        substituteInPlace static/yarn.lock \
                          --replace-warn '"electron-forge-maker-appimage@https://github.com/logseq/electron-forge-maker-appimage.git"' "\"electron-forge-maker-appimage@file:${gitDeps.electron_forge_maker_appimage_src}\"" \
                          --replace-warn "git+https://github.com/electron/node-gyp.git#${electronNodeGypRev}" "file:.nix-cache/git/electron-node-gyp" \
                          --replace-warn "https://github.com/electron/node-gyp#${electronNodeGypRev}" "file:.nix-cache/git/electron-node-gyp" \
                          --replace-warn "git+https://github.com/logseq/electron-forge-maker-appimage.git#${electronForgeMakerAppimageRev}" "file:${gitDeps.electron_forge_maker_appimage_src}" \
                          --replace-warn "https://github.com/logseq/electron-forge-maker-appimage.git#${electronForgeMakerAppimageRev}" "file:${gitDeps.electron_forge_maker_appimage_src}" \
                          --replace-warn '@electron_forge_maker_appimage_src@' "${gitDeps.electron_forge_maker_appimage_src}"
                        python3 ${./rewrite-static-lock.py} "$LOGSEQ_YARN_CACHE_RESOURCES" static/yarn.lock
                        mkdir -p static/.nix-cache/git
                        cp -R .nix-cache/git/electron-forge-maker-appimage static/.nix-cache/git/
                        cp -R .nix-cache/git/electron-node-gyp static/.nix-cache/git/
                        chmod -R u+w static/.nix-cache
                        substituteInPlace static/package.json \
                          --replace "https://github.com/logseq/electron-forge-maker-appimage.git" "file:.nix-cache/git/electron-forge-maker-appimage" \
                          --replace "git+https://github.com/logseq/electron-forge-maker-appimage.git" "file:.nix-cache/git/electron-forge-maker-appimage"

                        export ELECTRON_OVERRIDE_DIST_PATH=${electronDist}
                        mkdir -p "$ELECTRON_CACHE"
                        cp ${electronZipPath} "$ELECTRON_CACHE/${electronArchiveFile}"
                        chmod -R u+w "$ELECTRON_CACHE"
                        mkdir -p "$ELECTRON_BUILDER_CACHE"
                        cp -R ${electronBuilderCache}/. "$ELECTRON_BUILDER_CACHE/"
                        chmod -R u+w "$ELECTRON_BUILDER_CACHE"

                        yarn --cwd static config set yarn-offline-mirror "$LOGSEQ_YARN_CACHE_RESOURCES"
                        ELECTRON_SKIP_BINARY_DOWNLOAD=1 yarn --cwd static install --offline --frozen-lockfile --production=false --ignore-scripts
      LOGSEQ_ELECTRON_URL="https://github.com/electron/electron/releases/download/v${electronVersion}/${electronArchiveFile}"
      cache_dir_hash=$(LOGSEQ_ELECTRON_URL="$LOGSEQ_ELECTRON_URL" node -e "const {Cache} = require('./static/node_modules/@electron/get/dist/cjs/Cache'); const url = process.env.LOGSEQ_ELECTRON_URL; process.stdout.write(Cache.getCacheDirectory(url));")
            electron_cache_target="$ELECTRON_CACHE/$cache_dir_hash/${electronArchiveFile}"
            mkdir -p "$(dirname "$electron_cache_target")"
            cp ${electronZipPath} "$electron_cache_target"
            default_cache_root="$HOME/.cache/electron"
            mkdir -p "$default_cache_root/$cache_dir_hash"
            cp ${electronZipPath} "$default_cache_root/$cache_dir_hash/${electronArchiveFile}"
            LOGSEQ_ELECTRON_URL="https://github.com/electron/electron/releases/download/v${electronVersion}/SHASUMS256.txt"
            shasum_cache_dir=$(LOGSEQ_ELECTRON_URL="$LOGSEQ_ELECTRON_URL" node -e "const {Cache} = require('./static/node_modules/@electron/get/dist/cjs/Cache'); const url = process.env.LOGSEQ_ELECTRON_URL; process.stdout.write(Cache.getCacheDirectory(url));")
            shasum_cache_target="$ELECTRON_CACHE/$shasum_cache_dir/SHASUMS256.txt"
            mkdir -p "$(dirname "$shasum_cache_target")"
            cp ${electronShasumPath} "$shasum_cache_target"
            mkdir -p "$default_cache_root/$shasum_cache_dir"
            cp ${electronShasumPath} "$default_cache_root/$shasum_cache_dir/SHASUMS256.txt"
            export LOGSEQ_ELECTRON_SHASUMS=${electronShasumPath}
            rm -rf static/out
                        patchShebangs static/node_modules
                        if [ -d static/apps/tldraw-logseq/node_modules ]; then
                          patchShebangs static/apps/tldraw-logseq/node_modules
                        fi
            PATH="$PWD/static/node_modules/.bin:$PATH" ELECTRON_SKIP_BINARY_DOWNLOAD=1 yarn --cwd static run install-app-deps
            substituteInPlace static/node_modules/@electron/get/dist/cjs/index.js \
              --replace 'const details = Object.assign({}, artifactDetails);' 'const details = Object.assign({}, artifactDetails); if (details.artifactName === "SHASUMS256.txt" && process.env.LOGSEQ_ELECTRON_SHASUMS) { const tmpDir = await (0, utils_1.mkdtemp)(details.tempDirectory); const target = require("path").resolve(tmpDir, "SHASUMS256.txt"); await require("fs-extra").copy(process.env.LOGSEQ_ELECTRON_SHASUMS, target); return target; }' \
              --replace 'const cache = new Cache_1.Cache(details.cacheRoot);' 'const cacheRootOverride = details.cacheRoot || process.env.ELECTRON_CACHE; const cache = new Cache_1.Cache(cacheRootOverride); details.cacheRoot = cacheRootOverride;'
                  PATH="$PWD/static/node_modules/.bin:$PATH" DEBUG=electron-builder ELECTRON_SKIP_BINARY_DOWNLOAD=1 yarn --cwd static electron-forge package --platform linux --arch x64

                        runHook postBuild
    '';

    installPhase = ''
            runHook preInstall

            build_dir="static/out/Logseq-linux-x64"
            if [[ ! -d "$build_dir" ]]; then
              echo "error: expected directory $build_dir missing" >&2
              exit 1
            fi

            icon_src="$build_dir/resources/app/icon.png"
            if [[ -f "$icon_src" ]]; then
              install -Dm644 "$icon_src" "$out/share/icons/hicolor/512x512/apps/logseq.png"
            fi

            mkdir -p "$out/share/logseq"
            cp -r "$build_dir"/resources/app "$out/share/logseq/app"
            cp -r "$build_dir"/locales "$out/share/logseq/"
            shopt -s nullglob
            for pak in "$build_dir"/*.pak; do
              cp "$pak" "$out/share/logseq/"
            done
            shopt -u nullglob

            install -Dm755 /dev/stdin "$out/bin/logseq" <<'WRAPPER'
      #!/usr/bin/env bash
      set -euo pipefail

      store_root='@store_root@'
      store_app="$store_root/app"
      if [[ ! -d "$store_app" ]]; then
        store_app="$store_root/resources/app"
      fi
      if [[ ! -d "$store_app" && -f "$store_root/resources/app.asar" ]]; then
        store_app="$store_root/resources/app.asar"
      fi

      if [[ -n ''${NIXOS_OZONE_WL:-} && -n ''${WAYLAND_DISPLAY:-} ]]; then
        exec ${electronBinary} \
          "$store_app" \
          --ozone-platform-hint=auto \
          --enable-features=WaylandWindowDecorations \
          --enable-wayland-ime=true \
          "$@"
      else
        exec ${electronBinary} "$store_app" "$@"
      fi
      WRAPPER

            substituteInPlace "$out/bin/logseq" \
              --replace '@store_root@' "$out/share/logseq"

            runHook postInstall
    '';

    desktopItems = [
      (makeDesktopItem {
        name = "logseq";
        desktopName = "Logseq";
        exec = "logseq %U";
        terminal = false;
        icon = "logseq";
        startupWMClass = "Logseq";
        comment = "Privacy-first knowledge base";
        mimeTypes = [ "x-scheme-handler/logseq" ];
        categories = [
          "Utility"
          "Office"
        ];
      })
    ];

    meta = {
      description = "Logseq built from main";
      homepage = "https://github.com/logseq/logseq";
      license = lib.licenses.agpl3Only;
      platforms = lib.platforms.linux;
    };
  });

  logseqRunScript = writeShellScriptBin "logseq-fhs-runtime" ''
    export ELECTRON_DISABLE_SECURITY_WARNINGS=1
    export ELECTRON_IS_DEV=0
    export NIXOS_OZONE_WL=1
    export GTK_USE_PORTAL=1
    exec ${logseqUnwrapped}/bin/logseq --disable-setuid-sandbox "$@"
  '';

  logseqFhs = buildFHSEnv {
    name = "logseq-fhs";
    targetPkgs = runtimeDeps;
    runScript = "${logseqRunScript}/bin/logseq-fhs-runtime";
    extraInstallCommands = ''
      install -Dm644 ${logseqUnwrapped}/share/icons/hicolor/512x512/apps/logseq.png \
        $out/share/icons/hicolor/512x512/apps/logseq.png
      install -Dm644 ${logseqUnwrapped}/share/applications/logseq.desktop \
        $out/share/applications/logseq.desktop
      substituteInPlace $out/share/applications/logseq.desktop \
        --replace "logseq %U" "logseq-fhs %U"
      mkdir -p $out/bin
      ln -sf logseq-fhs $out/bin/logseq
    '';
  };

in
{
  "logseq-unwrapped" = logseqUnwrapped;
  "logseq-fhs" = logseqFhs;
}
