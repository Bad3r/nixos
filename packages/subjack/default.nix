{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "subjack";
  version = "3.0.0";

  src = fetchFromGitHub {
    owner = "haccer";
    repo = "subjack";
    tag = "v${version}";
    hash = "sha256-AHzBPtMpXy8ZG+lh7PpcvkJkdUal3ONhEQIhMVFSx+A=";
  };

  vendorHash = "sha256-Ma4kAcMfYm1ltOaAX39j78lxaAnWq03FYyB6rnKv9y8=";

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "DNS takeover scanner for finding hijackable subdomains";
    homepage = "https://github.com/haccer/subjack";
    changelog = "https://github.com/haccer/subjack/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "subjack";
    platforms = lib.platforms.linux;
  };
}
