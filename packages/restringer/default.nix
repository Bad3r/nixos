{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchurl,
  nodejs_22,
  python3,
}:

let
  # Fetch prebuilt isolated-vm binary for Node 22 (ABI v127)
  isolatedVmPrebuild = fetchurl {
    url = "https://github.com/laverdet/isolated-vm/releases/download/v5.0.4/isolated-vm-v5.0.4-node-v127-linux-x64.tar.gz";
    hash = "sha256-1HrBJ9xGroKS7Jttx4F+dE+JMsS1t8cU4cUO9yAOvbI=";
  };
in
buildNpmPackage rec {
  pname = "restringer";
  version = "2.1.0";

  src = fetchFromGitHub {
    owner = "HumanSecurity";
    repo = "restringer";
    rev = "v${version}";
    hash = "sha256-wUiYrQJVETMnwZ0gPcrcmGTSV/g6S2ZqP8RMJ+QPCDQ=";
  };

  nodejs = nodejs_22;

  # python3 needed for node-gyp (isolated-vm native module)
  nativeBuildInputs = [ python3 ];

  npmDepsHash = "sha256-mr+S9odeC59BlHprCWOchlAKjbvg0g/IR7Ec9u1A8iE=";

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

  meta = {
    description = "Deobfuscate Javascript with emphasis on reconstructing strings";
    homepage = "https://github.com/HumanSecurity/restringer";
    license = lib.licenses.mit;
    mainProgram = "restringer";
    platforms = lib.platforms.linux;
  };
}
