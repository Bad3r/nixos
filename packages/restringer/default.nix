# NOTE: restringer produces incorrect deobfuscation results in testing.
# For obfuscated JS, prefer webcrack instead.
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchurl,
  nodejs_22,
  python3,
}:

let
  pin = lib.importJSON ./hashes.json;

  # Fetch prebuilt isolated-vm binary for Node 22 (ABI v127)
  isolatedVmPrebuild = fetchurl {
    url = "https://github.com/laverdet/isolated-vm/releases/download/v${pin.isolatedVmVersion}/isolated-vm-v${pin.isolatedVmVersion}-${pin.isolatedVmNodeAbi}-${pin.isolatedVmPlatform}.tar.gz";
    hash = pin.isolatedVmPrebuildHash;
  };
in
buildNpmPackage rec {
  pname = "restringer";
  inherit (pin) version;

  src = fetchFromGitHub {
    owner = "HumanSecurity";
    repo = "restringer";
    rev = "v${version}";
    hash = pin.srcHash;
  };

  nodejs = nodejs_22;

  # python3 needed for node-gyp (isolated-vm native module)
  nativeBuildInputs = [ python3 ];

  inherit (pin) npmDepsHash;

  # Provide Node headers for node-gyp
  env.npm_config_nodedir = nodejs_22;
  makeCacheWritable = true;

  # Skip npm rebuild to avoid recompiling native modules
  npmRebuildFlags = [ "--ignore-scripts" ];

  # Inject prebuilt isolated-vm binary after npm install
  postConfigure = ''
    tar -xzf ${isolatedVmPrebuild} -C node_modules/isolated-vm
  '';

  # No build step needed - restringer is plain JS with native deps
  dontNpmBuild = true;

  passthru.updateScript = ./update.py;

  meta = {
    description = "Deobfuscate Javascript with emphasis on reconstructing strings";
    homepage = "https://github.com/HumanSecurity/restringer";
    license = lib.licenses.mit;
    mainProgram = "restringer";
    platforms = lib.platforms.linux;
  };
}
