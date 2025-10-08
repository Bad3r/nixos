# Correct NixOS Module Extraction Script
# This properly evaluates modules before extracting their options and metadata
{ flake, lib, pkgs }:
let
  # Helper to safely get attribute or default
  getAttrOr = default: path: attrs:
    lib.attrByPath path default attrs;

  # Helper to extract type information
  extractType = type:
    if type ? name then type.name
    else if type ? _type then type._type
    else "unknown";

  # Extract a single option's metadata
  extractOption = path: opt:
    let
      # Handle both evaluated and unevaluated options
      actualOpt = if opt ? _type && opt._type == "option" then opt else opt;
    in {
      path = lib.concatStringsSep "." path;
      type = extractType (actualOpt.type or null);
      description = actualOpt.description or null;
      default =
        if actualOpt ? default then
          if actualOpt.default ? _type then
            actualOpt.default._type
          else if builtins.isFunction actualOpt.default then
            null  # Can't serialize functions
          else
            actualOpt.default
        else null;
      example = actualOpt.example or null;
      readOnly = actualOpt.readOnly or false;
      internal = actualOpt.internal or false;
      visible = actualOpt.visible or true;
    };

  # Recursively extract options from an attribute set
  extractOptions = path: attrs:
    lib.flatten (lib.mapAttrsToList (name: value:
      if value ? _type && value._type == "option" then
        [ (extractOption (path ++ [name]) value) ]
      else if builtins.isAttrs value && !(value ? _type) then
        extractOptions (path ++ [name]) value
      else
        []
    ) attrs);

  # Process modules from the flake
  processFlakeModule = namespace: name: modulePath:
    let
      # Create a minimal evaluation for module inspection
      evaluated = lib.evalModules {
        modules = [
          {
            _file = modulePath;
            imports = [ modulePath ];
          }
        ];
        specialArgs = {
          inherit pkgs lib;
          # Add common module arguments
          config = {};
          options = {};
        };
      };

      # Extract module metadata if available
      meta = getAttrOr {} ["meta"] evaluated.config;

      # Extract all options defined by this module
      moduleOptions =
        if evaluated ? options then
          extractOptions [] evaluated.options
        else [];
    in {
      inherit namespace name;
      path = modulePath;
      description = meta.description or null;
      maintainers = meta.maintainers or [];
      options = moduleOptions;
      # Track if this is a role/profile module
      isRole = lib.hasPrefix "roles" namespace;
      isProfile = lib.hasPrefix "profiles" namespace;
      # Include any examples from meta
      examples = meta.examples or [];
      # Check if module has enable option (common pattern)
      hasEnable = lib.any (opt: lib.hasSuffix ".enable" opt.path) moduleOptions;
    };

  # Process all nixosModules from the flake
  nixosModules =
    if flake ? nixosModules then
      lib.mapAttrsToList (name: module:
        let
          namespace =
            if lib.hasInfix "." name then
              lib.head (lib.splitString "." name)
            else "root";
          moduleName =
            if lib.hasInfix "." name then
              lib.last (lib.splitString "." name)
            else name;
        in
          processFlakeModule namespace moduleName module._file or name
      ) flake.nixosModules
    else [];

  # Process homeManagerModules similarly
  homeManagerModules =
    if flake ? homeManagerModules then
      lib.mapAttrsToList (name: module:
        processFlakeModule "home-manager" name (module._file or name)
      ) flake.homeManagerModules
    else [];

  # Analyze module usage across configurations
  analyzeUsage =
    let
      configs = flake.nixosConfigurations or {};
    in
      lib.mapAttrs (hostName: hostConfig:
        let
          # Get the imports from the host configuration
          imports = hostConfig.config.imports or [];
          # Extract module names from imports
          usedModules = lib.filter (x: x != null) (map (imp:
            if builtins.isString imp then
              lib.last (lib.splitString "/" imp)
            else null
          ) imports);
        in {
          host = hostName;
          modules = usedModules;
          # Include some host metadata
          system = hostConfig.config.nixpkgs.system or "x86_64-linux";
          stateVersion = hostConfig.config.system.stateVersion or null;
        }
      ) configs;

  # Final output structure
  output = {
    # Metadata about the extraction
    meta = {
      version = "1.0.0";
      extractionDate = builtins.toString builtins.currentTime;
      flakeDescription = flake.description or null;
    };

    # All extracted modules
    modules = {
      nixos = nixosModules;
      homeManager = homeManagerModules;
    };

    # Usage analysis
    usage = analyzeUsage;

    # Statistics
    stats = {
      totalModules = (builtins.length nixosModules) + (builtins.length homeManagerModules);
      nixosModules = builtins.length nixosModules;
      homeManagerModules = builtins.length homeManagerModules;
      totalOptions = lib.foldl' (acc: m: acc + (builtins.length m.options)) 0
        (nixosModules ++ homeManagerModules);
      hostsTracked = builtins.length (builtins.attrNames (flake.nixosConfigurations or {}));
    };
  };

in {
  # Write the JSON output
  moduleData = pkgs.writeText "modules.json" (builtins.toJSON output);

  # Create an upload script
  uploadScript = pkgs.writeShellScriptBin "upload-module-docs" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Configuration
    API_URL="''${MODULE_DOCS_URL:-https://nixos-modules.workers.dev}"
    API_KEY="''${MODULE_DOCS_API_KEY}"

    # Validate environment
    if [ -z "$API_KEY" ]; then
      echo "Error: MODULE_DOCS_API_KEY not set"
      echo "Please set this environment variable with your API key"
      exit 1
    fi

    # Show what we're uploading
    echo "📊 Module Documentation Statistics:"
    echo "  - Total modules: ${toString output.stats.totalModules}"
    echo "  - NixOS modules: ${toString output.stats.nixosModules}"
    echo "  - Home Manager modules: ${toString output.stats.homeManagerModules}"
    echo "  - Total options: ${toString output.stats.totalOptions}"
    echo "  - Hosts tracked: ${toString output.stats.hostsTracked}"
    echo ""
    echo "📤 Uploading to: $API_URL"

    # Upload with proper error handling
    response=$(curl -X POST "$API_URL/api/v1/modules/batch" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -H "X-Module-Version: ${output.meta.version}" \
      -d @${output.moduleData} \
      --silent --show-error --write-out "\nHTTP_STATUS:%{http_code}" \
      --fail-with-body)

    http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d':' -f2)
    body=$(echo "$response" | sed '/HTTP_STATUS:/d')

    if [ "$http_status" = "200" ] || [ "$http_status" = "201" ]; then
      echo "✅ Successfully uploaded module documentation"
      echo "$body" | ${pkgs.jq}/bin/jq '.' 2>/dev/null || echo "$body"
    else
      echo "❌ Failed to upload module documentation"
      echo "HTTP Status: $http_status"
      echo "Response: $body"
      exit 1
    fi
  '';

  # Create a local inspection tool
  inspectScript = pkgs.writeShellScriptBin "inspect-modules" ''
    #!/usr/bin/env bash
    echo "📋 Module Documentation Summary"
    echo "================================"
    ${pkgs.jq}/bin/jq -r '
      "Total Modules: \(.stats.totalModules)",
      "Total Options: \(.stats.totalOptions)",
      "",
      "Top Modules by Options:",
      ((.modules.nixos + .modules.homeManager)
        | sort_by(-.options | length)
        | .[0:5]
        | .[]
        | "  - \(.name): \(.options | length) options")
    ' ${output.moduleData}
  '';
}