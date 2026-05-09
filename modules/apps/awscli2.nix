/*
  Package: awscli2
  Description: Unified tool to manage AWS services (AWS CLI v2).
  Homepage: https://aws.amazon.com/cli/
  Documentation: https://docs.aws.amazon.com/cli/latest/userguide/
  Repository: https://github.com/aws/aws-cli

  Summary:
    * Provides the `aws` command for provisioning, operating, and automating AWS resources from local shells and CI pipelines.
    * Supports multiple credential sources (environment, shared config, IAM Identity Center, `credential_process`) and structured output for scripting.

  Options:
    configure: Manage profiles, credentials, region, and output format under `~/.aws/`.
    sso login: Authenticate via AWS IAM Identity Center to obtain short-term credentials.
    s3: High-level filesystem-style commands (`cp`, `mv`, `sync`, `ls`, `rm`) for S3 buckets.
    s3api: Low-level access to the full S3 REST API surface.
    ec2: Manage EC2 instances, images, volumes, security groups, and related resources.
    iam: Manage IAM users, roles, policies, and access keys.
    sts: Issue temporary credentials and inspect the calling identity.
    --profile <name>: Select a named profile from `~/.aws/config`.
    --region <id>: Override the configured AWS region for a single invocation.
    --output <json|text|table|yaml|yaml-stream>: Choose the response rendering format.
    --query <JMESPath>: Filter and reshape responses client-side before rendering.

  Notes:
    * Tracks AWS CLI v2, the actively maintained major version. AWS CLI v1 (`nixpkgs#awscli`) is in maintenance mode.
    * Module options live at `programs.awscli2.extended` to match the nixpkgs attribute; the installed binary is `aws`.
*/
_:
let
  Awscli2Module =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.awscli2.extended;
    in
    {
      options.programs.awscli2.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable awscli2.";
        };

        package = lib.mkPackageOption pkgs "awscli2" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.awscli2 = Awscli2Module;
}
