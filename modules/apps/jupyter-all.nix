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
    * Every kernelspec the wrapper can reach is re-exported on JUPYTER_PATH so external clients such as the VS Code Jupyter extension can launch them.
    * JUPYTER_PATH precedes both the user data dir and `sys.prefix/share/jupyter` in `jupyter_path()`, and the first kernelspec of a given name wins, so this `python3` shadows both a user-installed `~/.local/share/jupyter/kernels/python3` and the `python3` spec `pip install ipykernel` writes into an active virtualenv.
*/
_:
let
  # The kernels named in the override land in a standalone
  # jupyter-kernel.create output that only the wrapped `jupyter` binary knows
  # about, through its own JUPYTER_PATH. Resolve that directory through the
  # wrapper instead of restating upstream's definition list.
  #
  # python3 is absent from that set when the override supplies no python
  # definition: replacing the definitions rather than extending them drops
  # jupyter-kernel.default and its absolute interpreter argv, leaving
  # ipykernel's own kernelspec, whose argv[0] is the bare string "python".
  # That resolves through PATH, and outside the wrapper PATH yields
  # programs.python.extended's hiPrio python313, which has no ipykernel. Only
  # kernel.json needs rewriting; buildEnv unfolds the python3 directory and
  # links ipykernel's logos next to it.
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
        # and the copy below would re-export ipykernel's relative-argv spec
        # and nothing else.
        if [ "$wrapperData" = "${package}/share/jupyter" ]; then
          echo "jupyter --paths resolved data[0] to the environment ($wrapperData), not the wrapper kernel dir" >&2
          exit 1
        fi

        install -d "$out/share/jupyter"
        cp -R "$wrapperData/kernels" "$out/share/jupyter/kernels"
        chmod -R u+w "$out/share/jupyter/kernels"

        # Only when the wrapper set has no python3 of its own. A definition
        # that supplies one carries a deliberate interpreter, display name,
        # and env, and jupyter-kernel.create already writes it with an
        # absolute argv.
        if [ ! -e "$out/share/jupyter/kernels/python3/kernel.json" ]; then
          ${package}/bin/python -c 'import ipykernel_launcher'
          install -d "$out/share/jupyter/kernels/python3"
          jq --arg interpreter '${package}/bin/python' '.argv[0] = $interpreter' \
            ${package}/share/jupyter/kernels/python3/kernel.json \
            > "$out/share/jupyter/kernels/python3/kernel.json"
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
          # hiPrio so the absolute-argv kernel.json wins the system-path
          # collision against the copy bundled in cfg.package.
          systemPackages = [
            cfg.package
            (lib.hiPrio kernelspecs)
          ];

          # NixOS links no /share/jupyter by default, so kernelspecs stay
          # reachable only through the wrapped `jupyter` binary, which sets
          # JUPYTER_PATH itself. profileRelativeSessionVariables expands the
          # suffix over environment.profiles, so a kernel installed through
          # home.packages is exported alongside the system one, and it feeds
          # both /etc/pam/environment (so editors started from the desktop
          # inherit it) and profileRelativeEnvVars for shells. Profiles that
          # ship no kernels cost nothing: _list_kernels_in skips a path that
          # is not a directory.
          # Only kernels: cfg.package's share/jupyter also carries
          # labextensions and nbconvert/templates, both resolved through
          # jupyter_path(), and exporting those would outrank a virtualenv's
          # own copies for `jupyter lab` and `jupyter nbconvert`. buildEnv
          # still creates the intermediate share/jupyter that JUPYTER_PATH
          # names.
          pathsToLink = [ "/share/jupyter/kernels" ];
          profileRelativeSessionVariables.JUPYTER_PATH = [ "/share/jupyter" ];
        };
      };
    };
in
{
  flake.nixosModules.apps.jupyter-all = JupyterAllModule;

  perSystem =
    { pkgs, ... }:
    {
      # system.path merges with ignoreCollisions = true, so a lost hiPrio race
      # degrades to a scrolled-past warning and a relative-argv kernel.json,
      # which is the bug this module exists to fix. Rebuild the same merge with
      # collisions fatal and assert the outcome. No runtimeCheck: realising the
      # merge pulls jupyter-all's 2.7 GiB closure, which is the weight
      # check.yml excludes host toplevels for.
      checks.jupyter-all-kernelspecs =
        let
          package = pkgs.jupyter-all;
          merged = pkgs.buildEnv {
            name = "jupyter-all-kernelspec-merge";
            paths = [
              package
              (pkgs.lib.hiPrio (mkKernelspecs pkgs package))
            ];
            pathsToLink = [ "/share/jupyter/kernels" ];
            ignoreCollisions = false;
          };
        in
        pkgs.runCommand "jupyter-all-kernelspecs-valid"
          {
            nativeBuildInputs = [ pkgs.jq ];
          }
          ''
            kernels=${merged}/share/jupyter/kernels

            argv0=$(jq -r '.argv[0]' "$kernels/python3/kernel.json")
            case "$argv0" in
              ${builtins.storeDir}/*) ;;
              *)
                echo "python3 argv[0] is '$argv0': the merge kept the relative-argv kernel.json from ${package.name}" >&2
                exit 1
                ;;
            esac

            if [ "$(find "$kernels" -mindepth 1 -maxdepth 1 -not -name python3 | wc -l)" -eq 0 ]; then
              echo "only python3 reached $kernels; the override kernels were not re-exported" >&2
              exit 1
            fi

            touch $out
          '';

      # The other branch of mkKernelspecs: a package whose definitions supply
      # their own python3 keeps that kernelspec verbatim. Byte comparison
      # rather than a field check, so any reappearance of the unconditional
      # rewrite fails. Eval-only for the same reason as the check above.
      checks.jupyter-kernelspecs-preserved =
        let
          package = pkgs.jupyter;
          specs = mkKernelspecs pkgs package;
        in
        pkgs.runCommand "jupyter-kernelspecs-preserved"
          {
            nativeBuildInputs = [ pkgs.jq ];
          }
          ''
            wrapperData=$(${package}/bin/jupyter --paths --json | jq -r '.data[0]')
            wrapperSpec="$wrapperData/kernels/python3/kernel.json"
            emitted=${specs}/share/jupyter/kernels/python3/kernel.json

            if [ ! -e "$wrapperSpec" ]; then
              echo "jupyter-kernel.default no longer supplies python3, so this check asserts nothing" >&2
              exit 1
            fi

            if ! cmp -s "$wrapperSpec" "$emitted"; then
              echo "the wrapper's python3 kernelspec was rewritten instead of preserved" >&2
              echo "wrapper:  $(jq -c . "$wrapperSpec")" >&2
              echo "emitted:  $(jq -c . "$emitted")" >&2
              exit 1
            fi

            touch $out
          '';
    };
}
