_: {
  flake.lib.agents._internal.mcp.raw = {
    sequential-thinking = {
      source = "nix";
      package = "mcp-server-sequential-thinking";
      clients = [
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Record structured reasoning steps for complex tasks.";
        accessNotes = "Useful for debugging, planning, and other nontrivial workflows.";
        example = "`sequentialthinking start`";
      };
    };

    memory = {
      source = "nix";
      package = "mcp-server-memory";
      clients = [ "codex" ];
      docs = {
        primaryUse = "Persist lightweight graph memory across runs.";
        accessNotes = "Enabled by default only for Codex.";
        example = "`memory search_nodes --query \"token endpoint\"`";
      };
    };

    context7 = {
      source = "nix";
      package = "context7-mcp";
      secretEnvVar = "CONTEXT7_API_KEY";
      clients = [
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Look up library IDs and documentation for coding tasks.";
        accessNotes = "Works without an API key; provision the standard local secret path for higher rate limits.";
        example = "`context7 resolve-library-id --name <library>`";
      };
    };

    cfdocs = {
      source = "http";
      url = "https://docs.mcp.cloudflare.com/mcp";
      clients = [
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Search Cloudflare documentation.";
        accessNotes = "Use for Workers, R2, Zero Trust, and other Cloudflare services through the streamable HTTP endpoint.";
        example = "`cfdocs search --query \"Workers KV\"`";
      };
    };

    cfbrowser = {
      source = "http";
      url = "https://browser.mcp.cloudflare.com/mcp";
      clients = [
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Render and capture live webpages.";
        accessNotes = "Useful for verifying UI changes against deployed sites through the streamable HTTP endpoint.";
        example = "`cfbrowser get-url-html --url <page>`";
      };
    };

    cfbuilds = {
      source = "http";
      url = "https://builds.mcp.cloudflare.com/mcp";
      clients = [ ];
      docs = {
        primaryUse = "Inspect Cloudflare builds and deployment activity.";
        accessNotes = "Available in the catalog but not enabled by default for Codex or Claude Code; uses the streamable HTTP endpoint.";
        example = "Use `/mcp` to inspect the available `cfbuilds` tools.";
      };
    };

    cfobservability = {
      source = "http";
      url = "https://observability.mcp.cloudflare.com/mcp";
      clients = [ ];
      docs = {
        primaryUse = "Query Cloudflare observability and logging data.";
        accessNotes = "Available in the catalog but not enabled by default for Codex or Claude Code; uses the streamable HTTP endpoint.";
        example = "Use `/mcp` to inspect the available `cfobservability` tools.";
      };
    };

    cfbindings = {
      source = "http";
      url = "https://bindings.mcp.cloudflare.com/mcp";
      clients = [ ];
      docs = {
        primaryUse = "Inspect Cloudflare bindings for Workers and Pages projects.";
        accessNotes = "Available in the catalog but not enabled by default for Codex or Claude Code; uses the streamable HTTP endpoint.";
        example = "Use `/mcp` to inspect the available `cfbindings` tools.";
      };
    };

    cfradar = {
      source = "http";
      url = "https://radar.mcp.cloudflare.com/mcp";
      clients = [ ];
      docs = {
        primaryUse = "Query Cloudflare Radar internet telemetry and trends.";
        accessNotes = "Available in the catalog but not enabled by default for Codex or Claude Code; uses the streamable HTTP endpoint.";
        example = "Use `/mcp` to inspect the available `cfradar` tools.";
      };
    };

    cfcontainers = {
      source = "http";
      url = "https://containers.mcp.cloudflare.com/mcp";
      clients = [ ];
      docs = {
        primaryUse = "Inspect Cloudflare Containers projects and instances.";
        accessNotes = "Available in the catalog but not enabled by default for Codex or Claude Code; uses the streamable HTTP endpoint.";
        example = "Use `/mcp` to inspect the available `cfcontainers` tools.";
      };
    };

    cfgraphql = {
      source = "http";
      url = "https://graphql.mcp.cloudflare.com/mcp";
      clients = [ ];
      docs = {
        primaryUse = "Run GraphQL queries against Cloudflare analytics endpoints.";
        accessNotes = "Available in the catalog but not enabled by default for Codex or Claude Code; uses the streamable HTTP endpoint.";
        example = "Use `/mcp` to inspect the available `cfgraphql` tools.";
      };
    };

    openaiDeveloperDocs = {
      source = "http";
      url = "https://developers.openai.com/mcp";
      clients = [ "codex" ];
      docs = {
        primaryUse = "Search OpenAI developer docs and API references.";
        accessNotes = "Enabled by default only for Codex through a streamable HTTP endpoint.";
        example = "`codex mcp add openaiDeveloperDocs --url https://developers.openai.com/mcp`";
      };
    };

    deepwiki = {
      source = "npx";
      package = "mcp-deepwiki@latest";
      clients = [
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Browse repository knowledge bases.";
        accessNotes = "Pass `owner/repo` to fetch docs.";
        example = "`deepwiki read_wiki_structure --repo owner/repo`";
      };
    };

    chrome-devtools = {
      source = "npx";
      package = "chrome-devtools-mcp@latest";
      args = [
        "--isolated"
        "--no-usage-statistics"
      ];
      timeout = 240;
      clients = [
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Control and inspect a live Chrome browser session.";
        accessNotes = "Local wrapper auto-detects Chrome or Chromium, passes `--executablePath`, and keeps `--isolated --no-usage-statistics`.";
        example = "`npx -y chrome-devtools-mcp@latest --executablePath=\"$(command -v google-chrome-stable)\" --isolated --no-usage-statistics`";
      };
    };

    playwright = {
      source = "npx";
      package = "@playwright/mcp@latest";
      args = [ "--isolated" ];
      timeout = 240;
      clients = [
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Automate browser interactions for UI and E2E checks.";
        accessNotes = "Local wrapper auto-detects Chrome or Chromium, passes `--executable-path`, and keeps an `--isolated` profile.";
        example = "`npx -y @playwright/mcp@latest --executable-path=\"$(command -v google-chrome-stable)\" --browser=chrome --isolated`";
      };
    };
  };
}
