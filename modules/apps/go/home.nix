/*
  Package: go
  Description: Go programming language compiler and tools.
  Homepage: https://go.dev/
*/

_: {
  flake.homeManagerModules.apps.go =
    {
      config,
      osConfig,
      lib,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "go" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.go = {
          enable = true;
          package = null;
        };

        # `go install` writes here under Go's default GOPATH.
        home.sessionPath = [ "${config.home.homeDirectory}/go/bin" ];
      };
    };
}
