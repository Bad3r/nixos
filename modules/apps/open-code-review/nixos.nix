/*
  Package: open-code-review
  Description: AI code review CLI that pairs deterministic file selection and rule matching with an LLM agent.
  Homepage: https://open-codereview.ai/
  Documentation: https://open-codereview.ai/docs
  Repository: https://github.com/alibaba/open-code-review

  Summary:
    * Reviews Git diffs or whole files with its own LLM agent and reports line-level findings.
    * Prints the reviewable files and their rule checklists for a coding agent that performs the review itself.

  Options:
    ocr review --from <ref>: Review the current branch against a base with the configured provider.
    ocr delegate preview --from <ref>: List the files a host agent reviews, without an LLM call.
    ocr delegate rule <path>...: Print the review rules for those files.
    ocr auth login: Sign in with ChatGPT for the chatgpt provider.

  Notes:
    * ~/.opencodereview/config.json is rendered from settings, so `ocr config set` cannot write it.
    * A configured provider stops ocr from falling back to OCR_LLM_* and ANTHROPIC_* API credentials in the environment or shell rc files.
    * OCR_ENABLE_TELEMETRY overrides telemetry.enabled, so the wrapper unsets it.
*/
{ inputs, ... }:
{
  flake.nixosModules.apps."open-code-review" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."open-code-review".extended;
      codexModel = lib.attrByPath [ "programs" "codex" "extended" "model" ] null config;
      jsonFormat = pkgs.formats.json { };

      wrapped = pkgs.symlinkJoin {
        name = "open-code-review-wrapped-${cfg.package.version}";
        paths = [ cfg.package ];
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        postBuild = ''
          wrapProgram $out/bin/ocr --unset OCR_ENABLE_TELEMETRY
        '';
        inherit (cfg.package) meta;
      };
    in
    {
      options.programs."open-code-review".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable open-code-review.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.open-code-review;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.open-code-review";
          description = "The open-code-review package to use.";
        };

        settings = lib.mkOption {
          inherit (jsonFormat) type;
          default = { };
          description = ''
            Contents of ~/.opencodereview/config.json, merged over this
            module's defaults: ChatGPT plan usage through Sign in with ChatGPT,
            the codex module's model, the medium review effort preset, and
            medium model reasoning.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        programs."open-code-review".extended.settings = {
          provider = lib.mkDefault "chatgpt";
          providers.chatgpt = {
            extra_body.reasoning.effort = lib.mkDefault "medium";
          }
          // lib.optionalAttrs (codexModel != null) { model = lib.mkDefault codexModel; };
          effort = lib.mkDefault "medium";
          telemetry.enabled = lib.mkDefault false;
        };

        environment.systemPackages = [ wrapped ];
      };
    };
}
