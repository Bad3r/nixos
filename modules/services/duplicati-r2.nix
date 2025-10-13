{ inputs, ... }:
let
  module =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.duplicati-r2;

      inherit (lib)
        attrByPath
        concatStringsSep
        escapeShellArg
        filter
        imap
        mkEnableOption
        mkIf
        mkOption
        mkPackageOption
        removeAttrs
        stringLength
        toInt
        types
        ;

      inherit (lib.strings)
        hasPrefix
        removePrefix
        replaceStrings
        splitString
        toLower
        ;

      parseConfigFile =
        path:
        let
          content = builtins.readFile path;
          lines = splitString "\n" content;
          filtered = filter (line: !(hasPrefix "#" line) && line != "") lines;
          cleaned = concatStringsSep "\n" filtered;
        in
        builtins.fromJSON cleaned;

      slugify =
        str:
        let
          sanitized = lib.strings.sanitizeDerivationName (toLower str);
        in
        if sanitized == "" then "target" else sanitized;

      stripLeadingSlash = path: removePrefix "/" path;

      encodeDestSubpath = path: replaceStrings [ " " ] [ "%20" ] (stripLeadingSlash path);

      cronToOnCalendar =
        cron:
        let
          fields = filter (f: f != "") (splitString " " cron);
        in
        if builtins.length fields != 5 then
          throw ''services.duplicati-r2: schedule "${cron}" must have exactly five cron fields''
        else
          let
            minute = builtins.elemAt fields 0;
            hour = builtins.elemAt fields 1;
            dom = builtins.elemAt fields 2;
            month = builtins.elemAt fields 3;
            dow = builtins.elemAt fields 4;

            pad =
              value:
              if value == "*" then
                "*"
              else if stringLength value == 1 then
                "0" + value
              else
                value;

            monthPart = if month == "*" then "*" else pad month;
            dayPart = if dom == "*" then "*" else pad dom;
            dowPart =
              if dow == "*" then
                ""
              else
                let
                  idx =
                    if builtins.match "^[0-9]+$" dow != null then
                      builtins.mod (toInt dow) 7
                    else
                      throw ''services.duplicati-r2: unsupported day-of-week "${dow}"'';
                  names = [
                    "Sun"
                    "Mon"
                    "Tue"
                    "Wed"
                    "Thu"
                    "Fri"
                    "Sat"
                  ];
                in
                "${builtins.elemAt names idx} ";

            minutePart = if minute == "*" then "*" else pad minute;
            hourPart = if hour == "*" then "*" else pad hour;
          in
          ''${dowPart}*-${monthPart}-${dayPart} ${hourPart}:${minutePart}:00'';

      defaultEnvFile = "/etc/duplicati/r2.env";
      defaultStateDir = "/var/lib/duplicati-r2";
      defaultBucket = "duplicati-nixos-backups";
      defaultRetention = "14D:1D,12M:1M";

      secretMappings = [
        {
          field = "awsAccessKeyId";
          env = "AWS_ACCESS_KEY_ID";
          selector = "duplicati-r2/awsAccessKeyId";
        }
        {
          field = "awsSecretAccessKey";
          env = "AWS_SECRET_ACCESS_KEY";
          selector = "duplicati-r2/awsSecretAccessKey";
        }
        {
          field = "accountId";
          env = "R2_ACCOUNT_ID";
          selector = "duplicati-r2/accountId";
        }
        {
          field = "s3EndpointHost";
          env = "R2_S3_ENDPOINT";
          selector = "duplicati-r2/s3EndpointHost";
        }
        {
          field = "s3EndpointUrl";
          env = "R2_S3_ENDPOINT_URL";
          selector = "duplicati-r2/s3EndpointUrl";
        }
        {
          field = "apiToken";
          env = "R2_API_TOKEN";
          selector = "duplicati-r2/apiToken";
        }
        {
          field = "bucket";
          env = "R2_BUCKET";
          selector = "duplicati-r2/bucket";
        }
        {
          field = "passphrase";
          env = "DUPLICATI_PASSPHRASE";
          selector = "duplicati-r2/passphrase";
        }
      ];

      credentialsSecretPath = inputs.secrets + "/duplicati-r2.yaml";
      credentialsExist = builtins.pathExists credentialsSecretPath;

      parsedConfig = if cfg.enable then removeAttrs (parseConfigFile cfg.configFile) [ "sops" ] else { };

      hostname = attrByPath [ "hostname" ] (attrByPath [
        "networking"
        "hostName"
      ] "nixos-host" config) parsedConfig;
      bucket = attrByPath [ "bucket" ] defaultBucket parsedConfig;
      stateDir = attrByPath [ "stateDir" ] defaultStateDir parsedConfig;
      envFile = attrByPath [ "environmentFile" ] defaultEnvFile parsedConfig;
      defaultTargetRetention = attrByPath [ "defaultRetention" ] defaultRetention parsedConfig;
      verifyConfig = attrByPath [ "verify" ] { } parsedConfig;
      verifyScheduleRaw = attrByPath [ "schedule" ] null verifyConfig;
      verifySamples = attrByPath [ "samples" ] 200 verifyConfig;

      rawTargets = attrByPath [ "targets" ] [ ] parsedConfig;

      processedTargets = imap (
        index: target:
        let
          path =
            let
              value = attrByPath [ "path" ] null target;
            in
            if value == null then throw "services.duplicati-r2: every target must define a path" else value;
          scheduleRaw =
            let
              value = attrByPath [ "schedule" ] null target;
            in
            if value == null then throw "services.duplicati-r2: every target must define a schedule" else value;
          retention = attrByPath [ "retention" ] defaultTargetRetention target;
          sanitizedName = slugify ("${builtins.toString index}-" + path);
          destSubpath = encodeDestSubpath path;
          serviceName = "duplicati-r2-backup-" + sanitizedName;
          dbPath = stateDir + "/" + serviceName + ".sqlite";
          onCalendar = cronToOnCalendar scheduleRaw;
        in
        {
          inherit
            path
            retention
            destSubpath
            serviceName
            dbPath
            onCalendar
            sanitizedName
            ;
          jobName = serviceName;
          timerName = serviceName;
        }
      ) rawTargets;

      targetsJson = pkgs.writeText "duplicati-r2-targets.json" (
        builtins.toJSON (
          map (target: {
            inherit (target)
              destSubpath
              dbPath
              jobName
              sanitizedName
              ;
          }) processedTargets
        )
      );

      duplicatiCli = lib.getExe' cfg.package "duplicati-cli";

      backupScript = pkgs.writeShellScript "duplicati-r2-backup.sh" ''
        set -euo pipefail

        if [[ $# -ne 8 ]]; then
          echo "Usage: $0 <hostname> <bucket> <source-path> <retention> <db-path> <dest-subpath> <env-file> <job-name>" >&2
          exit 64
        fi

        hostname="$1"
        bucket="$2"
        source_path="$3"
        retention="$4"
        db_path="$5"
        dest_subpath="$6"
        env_file="$7"
        job_name="$8"

        if [[ ! -f "$env_file" ]]; then
          echo "Duplicati R2: missing environment file $env_file" >&2
          exit 1
        fi
        # shellcheck disable=SC1090
        source "$env_file"

        if [[ -z ''${AWS_ACCESS_KEY_ID:-} || -z ''${AWS_SECRET_ACCESS_KEY:-} ]]; then
          echo "Duplicati R2: AWS credentials missing" >&2
          exit 1
        fi

        endpoint_host=''${R2_S3_ENDPOINT:-}
        if [[ -z "$endpoint_host" && -n ''${R2_ACCOUNT_ID:-} ]]; then
          endpoint_host="''${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
        fi

        if [[ -z "$endpoint_host" ]]; then
          echo "Duplicati R2: unable to determine endpoint host" >&2
          exit 1
        fi

        if [[ -n ''${R2_S3_ENDPOINT_URL:-} ]]; then
          export AWS_ENDPOINT_URL="''${R2_S3_ENDPOINT_URL}"
        else
          export AWS_ENDPOINT_URL="https://$endpoint_host"
        fi

        export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
        export AUTH_USERNAME="''${AWS_ACCESS_KEY_ID}"
        export AUTH_PASSWORD="''${AWS_SECRET_ACCESS_KEY}"

        if [[ -z ''${DUPLICATI_PASSPHRASE:-} ]]; then
          echo "Duplicati R2: DUPLICATI_PASSPHRASE missing from environment secret" >&2
          exit 1
        fi
        export PASSPHRASE="''${DUPLICATI_PASSPHRASE}"

        mkdir -p "$(dirname "$db_path")"

        dest="s3://$bucket/$hostname/$dest_subpath?use-ssl=true&s3-ext-disablehostprefixinjection=true&s3-disable-chunk-encoding=true&s3-client=minio&s3-server-name=$endpoint_host"

        exec ${duplicatiCli} \
          backup "$dest" "$source_path" \
          --backup-name="$job_name" \
          --dbpath="$db_path" \
          --retention-policy="$retention" \
          --full-result
      '';

      verifyScript = pkgs.writeShellScript "duplicati-r2-verify.sh" ''
        set -euo pipefail

        if [[ $# -ne 6 ]]; then
          echo "Usage: $0 <hostname> <bucket> <env-file> <samples> <targets-json> <state-dir>" >&2
          exit 64
        fi

        hostname="$1"
        bucket="$2"
        env_file="$3"
        samples="$4"
        targets_json="$5"
        state_dir="$6"

        if [[ ! -f "$env_file" ]]; then
          echo "Duplicati R2: missing environment file $env_file" >&2
          exit 1
        fi
        # shellcheck disable=SC1090
        source "$env_file"

        if [[ -z ''${AWS_ACCESS_KEY_ID:-} || -z ''${AWS_SECRET_ACCESS_KEY:-} ]]; then
          echo "Duplicati R2: AWS credentials missing" >&2
          exit 1
        fi

        endpoint_host=''${R2_S3_ENDPOINT:-}
        if [[ -z "$endpoint_host" && -n ''${R2_ACCOUNT_ID:-} ]]; then
          endpoint_host="''${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
        fi

        if [[ -z "$endpoint_host" ]]; then
          echo "Duplicati R2: unable to determine endpoint host" >&2
          exit 1
        fi

        if [[ -n ''${R2_S3_ENDPOINT_URL:-} ]]; then
          export AWS_ENDPOINT_URL="''${R2_S3_ENDPOINT_URL}"
        else
          export AWS_ENDPOINT_URL="https://$endpoint_host"
        fi

        export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
        export AUTH_USERNAME="''${AWS_ACCESS_KEY_ID}"
        export AUTH_PASSWORD="''${AWS_SECRET_ACCESS_KEY}"

        if [[ -z ''${DUPLICATI_PASSPHRASE:-} ]]; then
          echo "Duplicati R2: DUPLICATI_PASSPHRASE missing from environment secret" >&2
          exit 1
        fi
        export PASSPHRASE="''${DUPLICATI_PASSPHRASE}"

        if [[ ! -f "$targets_json" ]]; then
          echo "Duplicati R2: targets json $targets_json not found" >&2
          exit 1
        fi

        while IFS= read -r line; do
          dest_subpath=$(printf '%s' "$line" | ${pkgs.jq}/bin/jq -r '.destSubpath')
          job_name=$(printf '%s' "$line" | ${pkgs.jq}/bin/jq -r '.jobName')
          db_path=$(printf '%s' "$line" | ${pkgs.jq}/bin/jq -r '.dbPath')

          dest="s3://$bucket/$hostname/$dest_subpath?use-ssl=true&s3-ext-disablehostprefixinjection=true&s3-disable-chunk-encoding=true&s3-client=minio&s3-server-name=$endpoint_host"

          if [[ -n "$samples" && "$samples" != "null" ]]; then
            ${duplicatiCli} test "$dest" --samples="$samples" --dbpath="$db_path"
          else
            ${duplicatiCli} test "$dest" --dbpath="$db_path"
          fi
        done < <(${pkgs.jq}/bin/jq -c '.[]' "$targets_json")
      '';

      backupServices = builtins.listToAttrs (
        map (target: {
          name = target.serviceName;
          value = {
            description = "Duplicati R2 backup (${target.path})";
            after = [
              "network-online.target"
              "sops-install-secrets.service"
            ];
            wants = [ "network-online.target" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = concatStringsSep " " (
                [ backupScript ]
                ++ map escapeShellArg [
                  hostname
                  bucket
                  target.path
                  target.retention
                  target.dbPath
                  target.destSubpath
                  envFile
                  target.jobName
                ]
              );
              WorkingDirectory = stateDir;
            };
          };
        }) processedTargets
      );

      backupTimers = builtins.listToAttrs (
        map (target: {
          name = target.timerName;
          value = {
            description = "Schedule Duplicati R2 backup (${target.path})";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = target.onCalendar;
              Persistent = true;
              Unit = "${target.serviceName}.service";
            };
          };
        }) processedTargets
      );

      verifyService = {
        "duplicati-r2-verify" = {
          description = "Duplicati R2 integrity verification";
          after = [
            "network-online.target"
            "sops-install-secrets.service"
          ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = concatStringsSep " " (
              [ verifyScript ]
              ++ map escapeShellArg [
                hostname
                bucket
                envFile
                (builtins.toString verifySamples)
                targetsJson
                stateDir
              ]
            );
            WorkingDirectory = stateDir;
          };
        };
      };

      verifyTimer = {
        "duplicati-r2-verify" = {
          description = "Schedule Duplicati R2 verify";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cronToOnCalendar verifyScheduleRaw;
            Persistent = true;
            Unit = "duplicati-r2-verify.service";
          };
        };
      };
    in
    {
      options.services.duplicati-r2 = {
        enable = mkEnableOption "Duplicati R2 backup service";

        configFile = mkOption {
          type = types.path;
          description = "Absolute path to the sops-encrypted YAML file containing backup targets and schedules.";
          example = "/path/to/secrets/duplicati-config.yaml";
        };

        package = mkPackageOption pkgs "duplicati" { };
      };

      config = mkIf cfg.enable (
        let
          targetsDefined = processedTargets != [ ];
        in
        {
          assertions = [
            {
              assertion = cfg.configFile != null;
              message = "services.duplicati-r2.configFile must be provided";
            }
            {
              assertion = targetsDefined;
              message = "services.duplicati-r2 requires at least one target in the YAML configuration";
            }
            {
              assertion = credentialsExist;
              message = "Expected secrets/duplicati-r2.yaml to exist for credentials";
            }
          ];

          sops.secrets =
            builtins.listToAttrs (
              map (mapping: {
                name = "duplicati-r2/${mapping.field}";
                value = {
                  sopsFile = credentialsSecretPath;
                  format = "yaml";
                  key = mapping.selector;
                };
              }) secretMappings
            )
            // {
              "duplicati-r2/config" = {
                sopsFile = cfg.configFile;
                format = "yaml";
                path = "/run/duplicati-r2/config.yaml";
                owner = "root";
                mode = "0400";
              };
            };

          sops.templates."duplicati-r2-env" = {
            path = envFile;
            mode = "0400";
            owner = "root";
            group = "root";
            restartUnits =
              (map (target: "${target.serviceName}.service") processedTargets)
              ++ (if verifyScheduleRaw != null then [ "duplicati-r2-verify.service" ] else [ ]);
            content =
              concatStringsSep "\n" (
                map (
                  mapping:
                  let
                    placeholder = config.sops.placeholder."duplicati-r2/${mapping.field}";
                  in
                  "${mapping.env}=${placeholder}"
                ) secretMappings
              )
              + "\n";
          };

          environment.systemPackages = [ cfg.package ];

          systemd = {
            services = backupServices // (mkIf (verifyScheduleRaw != null) verifyService);
            timers = backupTimers // (mkIf (verifyScheduleRaw != null) verifyTimer);
            tmpfiles.rules = [
              "d ${stateDir} 0700 root root - -"
            ];
          };
        }
      );
    };
in
{
  flake.nixosModules.services.duplicati-r2 = module;
  flake.nixosModules."duplicati-r2" = module;
}
