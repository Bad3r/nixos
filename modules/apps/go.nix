/*
  Package: go
  Description: Go programming language toolchain and standard library.
  Homepage: https://go.dev/
  Documentation: https://go.dev/doc/
  Repository: https://go.googlesource.com/go

  Summary:
    * Provides the Go compiler, runtime, and tooling (`go build`, `go test`, `go mod`) for building statically linked binaries and services.
    * Includes module-aware dependency management, cross-compilation to multiple platforms, and built-in formatting/linting tools like `gofmt`.

  Options:
    go build [packages]: Compile packages into binaries or archives.
    go test [packages]: Run unit tests with benchmarking and coverage flags.
    go run <files|packages>: Build and execute code in one step.
    go mod tidy: Maintain module dependency graphs by adding/removing entries.
    go env: Inspect and configure Go environment variables (e.g. `GOPATH`, `GOMODCACHE`).

  Example Usage:
    * `go mod init example.com/project` — Initialize a new Go module.
    * `go build ./cmd/api` — Build a service located under `cmd/api`.
    * `go test ./... -race` — Run all project tests with the race detector enabled.
*/

{
  flake.nixosModules.apps.go =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.go ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.go ];
    };
}
