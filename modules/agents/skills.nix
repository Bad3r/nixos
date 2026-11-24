{ config, lib, ... }:
let
  reservedPublicSkillNames = [
    "list"
    "packDirsFor"
    "packs"
  ];

  registry = import ./_registry.nix { inherit lib; };
  inherit (registry) validClients;
  validateAllowedFields = registry.validateAllowedFields "skill";
  validateNonEmptyString = registry.validateNonEmptyString "skill";
  validatePackClients = registry.validateClients "skill pack";

  rawSkills = config.flake.lib.agents._internal.skills.raw;

  renderFrontmatter =
    fields: fieldOrder:
    let
      orderedKeys = lib.filter (key: fields ? ${key}) fieldOrder;
      extraKeys = lib.sort builtins.lessThan (
        lib.filter (key: !(lib.elem key fieldOrder)) (lib.attrNames fields)
      );
      keys = orderedKeys ++ extraKeys;
      lines = map (key: "${key}: ${builtins.toJSON fields.${key}}") keys;
    in
    ''
      ---
      ${lib.concatStringsSep "\n" lines}
      ---
    '';

  renderSkillDocument =
    {
      title,
      prelude ? "",
      body,
    }:
    lib.concatStringsSep "\n\n" (
      lib.filter (part: part != "") [
        "# ${title}"
        prelude
        body
      ]
    );

  validateOpenaiInterface =
    skillName: interface:
    let
      validatedInterface =
        validateAllowedFields "'${skillName}'.codex.openaiYaml.interface'" requiredFields
          interface;
      requiredFields = [
        "display_name"
        "short_description"
        "default_prompt"
      ];
      missingFields = lib.filter (field: !(validatedInterface ? ${field})) requiredFields;
    in
    if missingFields == [ ] then
      lib.mapAttrs (
        field: value: validateNonEmptyString skillName "codex.openaiYaml.interface.${field}" value
      ) validatedInterface
    else
      throw ''
        Agent skill '${skillName}' missing Codex interface fields: ${lib.concatStringsSep ", " missingFields}

        Example:
          codex.openaiYaml.interface = {
            display_name = "My Skill";
            short_description = "Does something useful";
            default_prompt = "Use this skill to...";
          };
      '';

  validateClientSpec =
    skillName: client: clientSpec:
    let
      allowedFields =
        {
          antigravity = [
            "frontmatter"
            "prelude"
          ];
          claude = [
            "frontmatter"
            "prelude"
          ];
          codex = [
            "frontmatter"
            "prelude"
            "openaiYaml"
          ];
        }
        .${client};
      validatedClientSpec = validateAllowedFields "'${skillName}'.${client}'" allowedFields clientSpec;
    in
    if client == "codex" then
      let
        openaiYaml = validatedClientSpec.openaiYaml or { };
        validatedOpenaiYaml = validateAllowedFields "'${skillName}'.codex.openaiYaml'" [
          "interface"
        ] openaiYaml;
        interface = validateOpenaiInterface skillName (validatedOpenaiYaml.interface or { });
      in
      validatedClientSpec
      // {
        openaiYaml = validatedOpenaiYaml // {
          inherit interface;
        };
      }
    else
      validatedClientSpec;

  validateSkillSpec =
    registryKey: spec:
    let
      allowedFields = [
        "name"
        "title"
        "description"
        "body"
        "app"
      ]
      ++ validClients;
      validatedSpec = validateAllowedFields "'${registryKey}'" allowedFields spec;
      name = validateNonEmptyString registryKey "name" validatedSpec.name;
      title = validateNonEmptyString registryKey "title" validatedSpec.title;
      description = validateNonEmptyString registryKey "description" validatedSpec.description;
      body = validateNonEmptyString registryKey "body" validatedSpec.body;
      app =
        if validatedSpec ? app then validateNonEmptyString registryKey "app" validatedSpec.app else null;
      presentClients = lib.filter (client: validatedSpec ? ${client}) validClients;
      validatedClients = lib.genAttrs presentClients (
        client: validateClientSpec name client validatedSpec.${client}
      );
    in
    if name != registryKey then
      throw "Agent skill registry key '${registryKey}' must match skill name '${name}'"
    else if lib.elem name reservedPublicSkillNames then
      throw "Agent skill '${name}' uses reserved public name '${name}'"
    else if app != null && !(config.flake.lib.nixos.hasApp app) then
      throw "Agent skill '${name}' names app '${app}', which has no flake.nixosModules.apps entry"
    else
      {
        inherit
          name
          title
          description
          body
          app
          ;
      }
      // validatedClients;

  renderCodexMarkdown =
    spec:
    let
      frontmatter =
        renderFrontmatter
          (
            {
              inherit (spec)
                name
                description
                ;
            }
            // (spec.codex.frontmatter or { })
          )
          [
            "name"
            "description"
          ];
      body = renderSkillDocument {
        inherit (spec)
          title
          body
          ;
        prelude = spec.codex.prelude or "";
      };
    in
    ''
      ${frontmatter}

      ${body}
    '';

  renderCodexOpenaiYaml =
    spec:
    let
      inherit (spec.codex.openaiYaml) interface;
    in
    ''
      interface:
        display_name: ${builtins.toJSON interface.display_name}
        short_description: ${builtins.toJSON interface.short_description}
        default_prompt: ${builtins.toJSON interface.default_prompt}
    '';

  renderClaudeMarkdown =
    spec:
    let
      frontmatter =
        renderFrontmatter
          (
            {
              inherit (spec)
                name
                description
                ;
            }
            // (spec.claude.frontmatter or { })
          )
          [
            "name"
            "description"
            "disable-model-invocation"
            "allowed-tools"
            "argument-hint"
          ];
      body = renderSkillDocument {
        inherit (spec)
          title
          body
          ;
        prelude = spec.claude.prelude or "";
      };
    in
    ''
      ${frontmatter}

      ${body}
    '';

  renderAntigravityMarkdown =
    spec:
    let
      frontmatter =
        renderFrontmatter
          (
            {
              inherit (spec)
                name
                description
                ;
            }
            // (spec.antigravity.frontmatter or { })
          )
          [
            "name"
            "description"
          ];
      body = renderSkillDocument {
        inherit (spec)
          title
          body
          ;
        prelude = spec.antigravity.prelude or "";
      };
    in
    ''
      ${frontmatter}

      ${body}
    '';

  compileSkill =
    registryKey: rawSpec:
    let
      spec = validateSkillSpec registryKey rawSpec;
      antigravityMarkdown = if spec ? antigravity then renderAntigravityMarkdown spec else null;
      codexMarkdown = if spec ? codex then renderCodexMarkdown spec else null;
      codexOpenaiYaml = if spec ? codex then renderCodexOpenaiYaml spec else null;
      claudeMarkdown = if spec ? claude then renderClaudeMarkdown spec else null;
    in
    {
      inherit (spec)
        name
        title
        description
        ;
      enabledOn =
        osConfig:
        spec.app == null || lib.attrByPath [ "programs" spec.app "extended" "enable" ] false osConfig;
    }
    // lib.optionalAttrs (spec ? antigravity) {
      antigravity = antigravityMarkdown;
    }
    // lib.optionalAttrs (spec ? claude) {
      claude = claudeMarkdown;
    }
    // lib.optionalAttrs (spec ? codex) {
      codex =
        pkgs:
        let
          skillMdFile = pkgs.writeText "codex-skill-${spec.name}-SKILL.md" codexMarkdown;
          openaiYamlFile = pkgs.writeText "codex-skill-${spec.name}-openai.yaml" codexOpenaiYaml;
        in
        {
          dir = pkgs.runCommand "codex-skill-${spec.name}" { } ''
            mkdir -p "$out/agents"
            cp ${skillMdFile} "$out/SKILL.md"
            cp ${openaiYamlFile} "$out/agents/openai.yaml"
          '';
          markdown = codexMarkdown;
          openaiYaml = codexOpenaiYaml;
        };
    };

  compiledSkills = lib.mapAttrs compileSkill rawSkills;

  rawPacks = config.flake.lib.agents._internal.skills.packs;

  compilePack =
    packName: rawPack:
    let
      validatedPack = validateAllowedFields "pack '${packName}'" [
        "src"
        "clients"
      ] rawPack;
      src = validatedPack.src or (throw "Agent skill pack '${packName}' requires field 'src'");
      clients = validatePackClients packName (
        validatedPack.clients or (throw "Agent skill pack '${packName}' requires field 'clients'")
      );
      entries = builtins.readDir src;
      skillNames = builtins.sort builtins.lessThan (
        lib.filter (name: entries.${name} == "directory" && builtins.pathExists "${src}/${name}/SKILL.md") (
          lib.attrNames entries
        )
      );
      reservedCollisions = lib.filter (name: lib.elem name reservedPublicSkillNames) skillNames;
      rawCollisions = lib.filter (name: rawSkills ? ${name}) skillNames;
    in
    assert lib.assertMsg (
      skillNames != [ ]
    ) "Agent skill pack '${packName}' contains no '<name>/SKILL.md' directories";
    assert lib.assertMsg (reservedCollisions == [ ])
      "Agent skill pack '${packName}' uses reserved skill name(s): ${lib.concatStringsSep ", " reservedCollisions}";
    assert lib.assertMsg (rawCollisions == [ ])
      "Agent skill pack '${packName}' collides with standalone skill(s): ${lib.concatStringsSep ", " rawCollisions}";
    {
      inherit
        clients
        src
        skillNames
        ;
      dirs = lib.genAttrs skillNames (skillName: "${src}/${skillName}");
    };

  compiledPacks = lib.mapAttrs compilePack rawPacks;

  packDirsFor =
    client:
    let
      matchingPacks = lib.attrValues (
        lib.filterAttrs (_: pack: lib.elem client pack.clients) compiledPacks
      );
      mergePack =
        acc: pack:
        lib.foldl' (
          innerAcc: skillName:
          assert lib.assertMsg (
            !(innerAcc ? ${skillName})
          ) "Agent skill '${skillName}' is declared by more than one skill pack for client '${client}'";
          innerAcc // { ${skillName} = pack.dirs.${skillName}; }
        ) acc pack.skillNames;
    in
    lib.foldl' mergePack { } matchingPacks;
in
{
  options.flake.lib.agents = {
    _internal.skills = {
      raw = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "Canonical raw skill specifications compiled into public client outputs.";
      };

      packs = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "Directory-based third-party skill packs linked into selected agent clients.";
      };
    };

    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Public compiled agent skills keyed by skill name plus discovery attrs.";
    };
  };

  config.flake.lib.agents.skills = compiledSkills // {
    list = compiledSkills;
    packs = compiledPacks;
    inherit packDirsFor;
  };
}
