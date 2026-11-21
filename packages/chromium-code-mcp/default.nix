{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

let
  pin = lib.importJSON ./hashes.json;
in
buildGoModule rec {
  pname = "chromium-code-mcp";
  inherit (pin) version;

  src = fetchFromGitHub {
    owner = "dgavrilov";
    repo = "chromium-code-mcp";
    rev = "v${version}";
    hash = pin.srcHash;
  };

  subPackages = [ "cmd/chromium-code-mcp" ];

  inherit (pin) vendorHash;

  ldflags = [
    "-s"
    "-w"
    "-X github.com/dgavrilov/chromium-code-mcp.Version=${version}"
  ];

  meta = {
    description = "MCP server for Chromium code search, Gerrit, LUCI, and the issue tracker";
    homepage = "https://github.com/dgavrilov/chromium-code-mcp";
    changelog = "https://github.com/dgavrilov/chromium-code-mcp/releases/tag/v${version}";
    license = lib.licenses.bsd3;
    mainProgram = "chromium-code-mcp";
    platforms = lib.platforms.unix;
  };

  passthru.updateScript = ./update.py;
}
