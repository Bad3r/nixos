{ config, lib, ... }:
let
  reservedPublicSkillNames = [ "list" ];

  validClients = [
    "claude"
    "codex"
  ];

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

  validateNonEmptyString =
    skillName: field: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "Agent skill '${skillName}' requires non-empty string field '${field}'";

  validateAllowedFields =
    context: allowedFields: attrs:
    let
      extraFields = lib.filter (field: !(lib.elem field allowedFields)) (lib.attrNames attrs);
    in
    if extraFields == [ ] then
      attrs
    else
      throw "Agent skill ${context} has unknown fields: ${lib.concatStringsSep ", " extraFields}";

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
      throw "Agent skill '${skillName}' missing Codex interface fields: ${lib.concatStringsSep ", " missingFields}";

  validateClientSpec =
    skillName: client: clientSpec:
    let
      allowedFields =
        {
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
      ]
      ++ validClients;
      validatedSpec = validateAllowedFields "'${registryKey}'" allowedFields spec;
      name = validateNonEmptyString registryKey "name" validatedSpec.name;
      title = validateNonEmptyString registryKey "title" validatedSpec.title;
      description = validateNonEmptyString registryKey "description" validatedSpec.description;
      body = validateNonEmptyString registryKey "body" validatedSpec.body;
      presentClients = lib.filter (client: validatedSpec ? ${client}) validClients;
      validatedClients = lib.genAttrs presentClients (
        client: validateClientSpec name client validatedSpec.${client}
      );
    in
    if name != registryKey then
      throw "Agent skill registry key '${registryKey}' must match skill name '${name}'"
    else if lib.elem name reservedPublicSkillNames then
      throw "Agent skill '${name}' uses reserved public name '${name}'"
    else
      {
        inherit
          name
          title
          description
          body
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

  compileSkill =
    registryKey: rawSpec:
    let
      spec = validateSkillSpec registryKey rawSpec;
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
in
{
  options.flake.lib.agents = {
    _internal.skills.raw = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Canonical raw skill specifications compiled into public client outputs.";
    };

    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Public compiled agent skills keyed by skill name plus discovery attrs.";
    };
  };

  config.flake.lib.agents.skills = compiledSkills // {
    list = compiledSkills;
  };
}
