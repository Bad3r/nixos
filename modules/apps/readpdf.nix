/*
  Package: readpdf
  Description: Extract OCR text from PDFs using OCRmyPDF sidecar output.
  Homepage: nil
  Documentation: nil
  Repository: nil

  Summary:
    * Provides a focused `readpdf` command for text extraction from image-based or broken-text-layer PDFs.
    * Defaults to stdout while still allowing explicit sidecar text files.

  Options:
    -p, --pages <pages>: Limit OCR to pages, ranges, or comma-separated selectors such as `3`, `2-5`, or `1,3,7-10`.
    -o, --output <file>: Write recognized text to a file instead of stdout.
    -h, --help: Print usage information.

  Notes:
    * Wraps OCRmyPDF force mode because PDFs with bad embedded text layers need a fresh OCR pass.
    * Sends OCRmyPDF's required searchable-PDF output to `/dev/null` for stdout mode.
*/
_:
let
  ReadPdfModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.readpdf.extended;

      readpdfWrapper = pkgs.writeShellApplication {
        name = "readpdf";
        runtimeInputs = [
          cfg.package
          pkgs.coreutils
        ];
        text = ''
          usage() {
            cat <<'EOF'
          readpdf - extract OCR text from a PDF

          Usage:
            readpdf [OPTIONS] INPUT.pdf [OUTPUT.txt]
            readpdf [OPTIONS] -o OUTPUT.txt INPUT.pdf

          Arguments:
            INPUT.pdf             PDF to OCR.
            OUTPUT.txt            Optional text output path. Defaults to stdout.

          Options:
            -p, --pages PAGES     Limit OCR to pages, ranges, or comma-separated selectors.
                                  Examples: 3, 2-5, 1,3,7-10.
            -o, --output FILE     Write recognized text to FILE instead of stdout.
            -h, --help            Print this help and exit.

          Examples:
            readpdf scan.pdf
            readpdf scan.pdf scan.txt
            readpdf -o scan.txt scan.pdf
            readpdf -p 3 scan.pdf
            readpdf -p 1,3,7-10 scan.pdf scan.txt
          EOF
          }

          pages=""
          output=""
          positional=()

          while [[ $# -gt 0 ]]; do
            case "$1" in
              -p|--pages)
                if [[ -z "''${2:-}" ]]; then
                  echo "readpdf: missing value for $1" >&2
                  exit 2
                fi
                pages="$2"
                shift 2
                ;;
              --pages=*)
                pages="''${1#*=}"
                if [[ -z "$pages" ]]; then
                  echo "readpdf: --pages= requires a non-empty value" >&2
                  exit 2
                fi
                shift
                ;;
              -o|--output)
                if [[ -z "''${2:-}" ]]; then
                  echo "readpdf: missing value for $1" >&2
                  exit 2
                fi
                output="$2"
                shift 2
                ;;
              --output=*)
                output="''${1#*=}"
                if [[ -z "$output" ]]; then
                  echo "readpdf: --output= requires a non-empty value" >&2
                  exit 2
                fi
                shift
                ;;
              -h|--help)
                usage
                exit 0
                ;;
              --)
                shift
                positional+=("$@")
                break
                ;;
              -*)
                echo "readpdf: unknown option: $1" >&2
                echo "readpdf: see readpdf --help" >&2
                exit 2
                ;;
              *)
                positional+=("$1")
                shift
                ;;
            esac
          done

          if (( ''${#positional[@]} < 1 || ''${#positional[@]} > 2 )); then
            usage >&2
            exit 2
          fi

          input="''${positional[0]}"
          if [[ -n "$output" && ''${#positional[@]} -eq 2 ]]; then
            echo "readpdf: output specified twice" >&2
            exit 2
          fi
          if [[ ''${#positional[@]} -eq 2 ]]; then
            output="''${positional[1]}"
          fi

          if [[ ! -f "$input" ]]; then
            echo "readpdf: input file not found: $input" >&2
            exit 1
          fi

          page_args=()
          if [[ -n "$pages" ]]; then
            page_args=(--pages "$pages")
          fi

          if [[ -n "$output" && "$output" != "-" ]]; then
            mkdir -p -- "$(dirname -- "$output")"
            exec ocrmypdf \
              -q \
              --force-ocr \
              --output-type none \
              "''${page_args[@]}" \
              --sidecar "$output" \
              "$input" \
              -
          fi

          exec ocrmypdf \
            -q \
            --force-ocr \
            "''${page_args[@]}" \
            --sidecar - \
            "$input" \
            /dev/null
        '';
      };
    in
    {
      options.programs.readpdf.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the readpdf OCR text extraction wrapper.";
        };

        package = lib.mkPackageOption pkgs "ocrmypdf" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ readpdfWrapper ];
      };
    };
in
{
  flake.nixosModules.apps.readpdf = ReadPdfModule;
}
