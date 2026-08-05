/*
  Package: jupyter-all
  Description: Jupyter wrapper bundling JupyterLab, the classic notebook server, and a curated set of language kernels.
  Homepage: https://jupyter.org/
  Documentation: https://docs.jupyter.org/
  Repository: https://github.com/jupyter/notebook

  Summary:
    * Provides a single environment with `jupyter`, `jupyter-lab`, `jupyter-notebook`, `jupyter-console`, `jupyter-nbconvert`, and `ipython` entry points.
    * Ships Clojure (Clojupyter), Octave, R (Ark), and Ruby (IRuby) kernels through the nixpkgs override; the Python kernelspec comes from ipykernel in the environment itself, not from the override.

  Options:
    notebook: Launch the classic web-based Jupyter Notebook server.
    lab: Start the JupyterLab next-generation notebook IDE.
    console: Open a terminal-based interactive kernel session.
    nbconvert <input>: Convert notebooks to HTML, PDF, slides, Markdown, scripts, or other formats.
    kernelspec <subcommand>: Manage installed Jupyter kernels (list, install, remove, provision).
    server: Run only the headless Jupyter server backend without a UI.

  Notes:
    * `jupyter-all` is `jupyter.override` from nixpkgs that swaps the default kernel definition set for the Clojure, Octave, R, and Ruby ones.
    * The Wolfram kernel is intentionally excluded upstream because it is unfree.
    * Those four kernels live in a standalone `jupyter-kernel.create` output that only the wrapped `jupyter` binary knows about, so they are re-exported on JUPYTER_PATH for external clients such as the VS Code Jupyter extension.
    * No `python3` kernelspec is exported, deliberately; see the comment on `mkKernelspecs`. Python notebooks want a per-project virtualenv (`uv venv && uv pip install ipykernel`) selected as the interpreter.
*/
_:
let
  # Copies the kernels out of the standalone jupyter-kernel.create output that
  # reaches the wrapper only through its own JUPYTER_PATH prefix. Resolved
  # through `jupyter --paths` rather than by restating upstream's definition
  # list, so a change to the override's kernel set carries over.
  #
  # python3 is dropped rather than exported. jupyter_path() ranks JUPYTER_PATH
  # above sys.prefix and KernelSpecManager keeps the first spec per name, so a
  # python3 here shadows the one `pip install ipykernel` writes into an active
  # virtualenv, and it would launch a fixed store interpreter carrying ipykernel
  # and none of the project's dependencies. The kernels kept below have no such
  # conflict: nothing else on JUPYTER_PATH claims those names.
  mkKernelspecs =
    pkgs: package:
    pkgs.runCommand "jupyter-all-kernelspecs"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        wrapperData=$(${package}/bin/jupyter --paths --json | jq -r '.data[0]')

        # jupyter_path() lists JUPYTER_PATH ahead of sys.prefix, so data[0]
        # landing on the environment itself means the injected entry is gone
        # and the copy below would take ipykernel's kernels directory instead.
        if [ "$wrapperData" = "${package}/share/jupyter" ]; then
          echo "jupyter --paths resolved data[0] to the environment ($wrapperData), not the wrapper kernel dir" >&2
          exit 1
        fi

        install -d "$out/share/jupyter"
        cp -R "$wrapperData/kernels" "$out/share/jupyter/kernels"
        chmod -R u+w "$out/share/jupyter/kernels"
        rm -rf "$out/share/jupyter/kernels/python3"

        if [ -z "$(ls -A "$out/share/jupyter/kernels")" ]; then
          echo "no kernelspecs left to export from $wrapperData" >&2
          exit 1
        fi
      '';

  JupyterAllModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."jupyter-all".extended;
      kernelspecs = mkKernelspecs pkgs cfg.package;
    in
    {
      options.programs."jupyter-all".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable jupyter-all.";
        };

        package = lib.mkPackageOption pkgs "jupyter-all" { };
      };

      config = lib.mkIf cfg.enable {
        environment = {
          systemPackages = [ cfg.package ];

          # Named by absolute path rather than linked into the profiles through
          # environment.pathsToLink: cfg.package's own share/jupyter/kernels is
          # a symlink to ipykernel's directory, whose sole python3 spec carries
          # the bare argv[0] "python". Linking that subpath would export it, and
          # outside the wrapper it resolves through PATH to
          # programs.python.extended's hiPrio pkgs.python3, which has no
          # ipykernel. sessionVariables feeds /etc/pam/environment, so editors
          # started from the desktop inherit it, and environment.variables for
          # shells.
          sessionVariables.JUPYTER_PATH = [ "${kernelspecs}/share/jupyter" ];
        };
      };
    };
in
{
  flake.nixosModules.apps.jupyter-all = JupyterAllModule;
}
