_: {
  flake.lib.agents._internal.mcp.raw = {
    # Off: mcp-servers-nix compiles it with nixpkgs typescript, TypeScript 7 since nixpkgs#560311, which
    # no longer auto-includes @types/node, so tsc fails on `process`.
    sequential-thinking = {
      source = "nix";
      package = "mcp-server-sequential-thinking";
      clients = [ ];
      docs = {
        primaryUse = "Record structured reasoning steps for complex tasks.";
        accessNotes = "Available in the catalog but not enabled by default for Codex or Claude Code.";
        example = "`sequentialthinking start`";
      };
    };

    memory = {
      source = "nix";
      package = "mcp-server-memory";
      clients = [ ];
      docs = {
        primaryUse = "Persist lightweight graph memory across runs.";
        accessNotes = "Available in the catalog but not enabled by default for Codex or Claude Code.";
        example = "`memory search_nodes --query \"token endpoint\"`";
      };
    };

    context7 = {
      source = "nix";
      package = "context7-mcp";
      secretEnvVar = "CONTEXT7_API_KEY";
      network.allowedDomains = [ "context7.com" ];
      clients = [ "codex" ];
      docs = {
        primaryUse = "Look up library IDs and documentation for coding tasks.";
        accessNotes = "Works without an API key; provision the standard local secret path for higher rate limits. Scoped to Codex: Claude Code consumes the claude.ai Context7 connector instead, so the local server is dropped there to avoid a duplicate registration.";
        example = "`context7 resolve-library-id --name <library>`";
      };
    };

    cfdocs = {
      source = "http";
      url = "https://docs.mcp.cloudflare.com/mcp";
      clients = [ ];
      docs = {
        primaryUse = "Search Cloudflare documentation.";
        accessNotes = "Use for Workers, R2, Zero Trust, and other Cloudflare services through the streamable HTTP endpoint.";
        example = "`cfdocs search --query \"Workers KV\"`";
      };
    };

    cfbrowser = {
      source = "http";
      url = "https://browser.mcp.cloudflare.com/mcp";
      network.mode = "full";
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
      network.allowedDomains = [ "*.openai.com" ];
      clients = [ "codex" ];
      docs = {
        primaryUse = "Search OpenAI developer docs and API references.";
        accessNotes = "Enabled by default only for Codex through a streamable HTTP endpoint.";
        example = "`codex mcp add openaiDeveloperDocs --url https://developers.openai.com/mcp`";
      };
    };

    gh_grep = {
      source = "http";
      url = "https://mcp.grep.app";
      clients = [
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Search public GitHub code indexed by grep.app.";
        accessNotes = "Enabled by default for Codex and Claude Code through the remote grep.app HTTP endpoint.";
        example = "Use `/mcp` to inspect the available `gh_grep` tools.";
      };
    };

    deepwiki = {
      source = "http";
      url = "https://mcp.deepwiki.com/mcp";
      clients = [
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Browse repository knowledge bases.";
        accessNotes = "Official remote no-authentication-required HTTP endpoint; pass `owner/repo` to the DeepWiki tools.";
        example = "`claude mcp add -s user -t http deepwiki https://mcp.deepwiki.com/mcp`";
      };
    };

    chrome-devtools = {
      source = "npx";
      package = "chrome-devtools-mcp@latest";
      network.mode = "full";
      args = [
        "--isolated"
        "--no-usage-statistics"
        "--no-performance-crux"
        # Every optional tool category, with the coordinate, memory, and DevTools-UI tools.
        "--category-network-mocks"
        "--category-extensions"
        "--category-experimental-third-party"
        "--category-experimental-webmcp"
        "--category-pwa"
        "--category-webauthn"
        "--experimental-vision"
        "--memory-debugging"
        "--experimental-devtools"
        # WebMCP tools exist only when Chrome ships the feature.
        "--chrome-arg=--enable-features=WebMCP"
      ];
      timeout = 240;
      clients = [
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Control and inspect a live Chrome browser session.";
        accessNotes = "Shared wrapper forces usage statistics and CrUX off and disables update checks and npm update notifications. Standalone `--` is rejected so required flags cannot become positional arguments. Runs the full tool set: every optional category (network mocks, extensions, WebMCP, third-party page tools, PWA, WebAuthn), the coordinate, memory, and DevTools-UI tools, and WebMCP enabled in Chrome. Needs Chrome 150 or newer for WebMCP. Both clients use it instead of the upstream Claude plugin. Browser traffic and npm package resolution remain enabled; these controls are not a network sandbox.";
        example = "`npx -y chrome-devtools-mcp@latest --executablePath=\"$(command -v google-chrome-stable)\" --isolated --no-usage-statistics --no-performance-crux`";
      };
    };

    firefox = {
      source = "npx";
      # The browser is Camoufox, so the server exists only where that app's row is on.
      app = "camoufox";
      package = "@mozilla/firefox-mcp-moz@latest";
      network.mode = "full";
      args = [
        # Every module, including the privileged, preference, relaunch, and raw BiDi ones.
        "--tool-preset"
        "all"
        "--pref"
        "toolkit.telemetry.enabled=false"
        "--pref"
        "toolkit.telemetry.unified=false"
        "--pref"
        "toolkit.telemetry.archive.enabled=false"
        "--pref"
        "datareporting.healthreport.uploadEnabled=false"
        "--pref"
        "datareporting.policy.dataSubmissionEnabled=false"
        "--pref"
        "browser.ping-centre.telemetry=false"
        "--pref"
        "browser.newtabpage.activity-stream.feeds.telemetry=false"
        "--pref"
        "browser.newtabpage.activity-stream.telemetry=false"
        "--pref"
        "app.shield.optoutstudies.enabled=false"
        "--pref"
        "app.normandy.enabled=false"
      ];
      timeout = 240;
      clients = [
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Control and inspect a live Camoufox (Firefox) session, including privileged contexts.";
        accessNotes = "Runs the Mozilla build of the server with every tool module, driving the camoufox app's browser, so it is present only where that app's row is on. Camoufox does not replace geckodriver, which still translates the server's WebDriver calls; the wrapper puts it on PATH. The wrapper sets MOZ_REMOTE_ALLOW_SYSTEM_ACCESS=1 for the privileged modules and turns off Selenium Manager statistics and the Firefox crash reporter; Firefox telemetry prefs are off. Each session uses a fresh temporary profile. The privileged modules give the agent browser-privileged access with no web-content sandbox, so it can act outside the page.";
        example = "`npx -y @mozilla/firefox-mcp-moz@latest --tool-preset all --firefox-path \"$(command -v camoufox)\"`";
      };
    };

    sbx = {
      source = "app";
      app = "sbx";
      program = "sbx-mcp";
      # A call lasts up to a sandbox's longest TTL; Codex stops waiting after 300 s by default.
      toolTimeout = cfg: cfg.limits.maxTtl * 3600;
      autoApprove = true;
      clients = [
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Run untrusted code in disposable sbx VMs.";
        accessNotes = "Local stdio server of the `sbx` app, present only where its row is on; tools mirror the `sbx` verbs and their `--json` output.";
        example = "`run` with `{\"base\": \"nixos\", \"command\": [\"uname\", \"-a\"]}`";
      };
    };

    node_repl = {
      source = "app";
      app = "chatgpt";
      program = cfg: "${cfg.finalPackage.unwrapped}/lib/chatgpt/resources/cua_node/bin/node_repl";
      timeout = 120;
      clients = [ "codex" ];
      docs = {
        primaryUse = "Run JavaScript in the ChatGPT browser runtime.";
        accessNotes = "Requires the ChatGPT desktop package. Browser access uses the desktop session connection.";
        example = "Use `/mcp` to inspect the available `node_repl` tools.";
      };
    };

    playwright = {
      source = "npx";
      package = "@playwright/mcp@latest";
      network.mode = "full";
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
