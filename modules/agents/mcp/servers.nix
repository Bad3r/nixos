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
        accessNotes = "Available in the catalog but not enabled by default for Codex, Claude Code, or Antigravity.";
        example = "`sequentialthinking start`";
      };
    };

    memory = {
      source = "nix";
      package = "mcp-server-memory";
      clients = [ ];
      docs = {
        primaryUse = "Persist lightweight graph memory across runs.";
        accessNotes = "Available in the catalog but not enabled by default for Codex, Claude Code, or Antigravity.";
        example = "`memory search_nodes --query \"token endpoint\"`";
      };
    };

    context7 = {
      source = "nix";
      package = "context7-mcp";
      secretEnvVar = "CONTEXT7_API_KEY";
      network.allowedDomains = [ "context7.com" ];
      clients = [
        "antigravity"
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Look up library IDs and documentation for coding tasks.";
        accessNotes = "Works without an API key; provision `~/.local/share/context7/api-key` for higher rate limits. Shared across Codex, Antigravity, and Claude Code, where `claude.ai Context7` is denied so every client routes through `codemode`.";
        example = "Use `codemode` `search` (`await codemode.tools(\"context7\")`) or `execute` (`await codemode.context7.resolve_library_id(...)`).";
      };
    };

    cloudflare-api = {
      source = "http";
      url = "https://mcp.cloudflare.com/mcp";
      secretHeader = {
        name = "Authorization";
        prefix = "Bearer ";
        relativePath = "cloudflare/api-key";
      };
      clients = [
        "antigravity"
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Search Cloudflare docs and run authenticated Cloudflare API actions through Cloudflare's Code Mode MCP server.";
        accessNotes = "Authenticates host-side with the SOPS-provisioned Bearer token at `~/.local/share/cloudflare/api-key` (`CF_MCP_API_KEY` from `secrets/cloudflare.yaml`). User API tokens (`cfut_*`) require `User Details: Read` and `Account Settings: Read`; account API tokens (`cfat_*`) require `Account Resources: Read`. Replaces the separate Cloudflare MCP endpoints (`cfdocs`, `cfbrowser`, `cfbuilds`, `cfobservability`, `cfbindings`, `cfradar`, `cfcontainers`, `cfgraphql`) and the marketplace Cloudflare plugins so all clients route through `codemode`.";
        example = "Use `codemode` `search` for `cloudflare_api` tools (`docs`, `search`, `execute`, `whoami`).";
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
        example = "Use `codemode` `search` (`await codemode.tools(\"openaiDeveloperDocs\")`).";
      };
    };

    gh_grep = {
      source = "http";
      url = "https://mcp.grep.app";
      clients = [
        "antigravity"
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Search public GitHub code indexed by grep.app.";
        accessNotes = "Enabled by default for Codex, Claude Code, and Antigravity through the remote grep.app HTTP endpoint.";
        example = "Use `codemode` `search` (`await codemode.tools(\"gh_grep\")`).";
      };
    };

    google-developer-knowledge = {
      source = "http";
      url = "https://developerknowledge.googleapis.com/mcp";
      disabled = true;
      secretHeader = {
        name = "X-Goog-Api-Key";
        relativePath = "google-developer-knowledge/api-key";
      };
      clients = [
        "antigravity"
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Search and retrieve official Google developer documentation.";
        accessNotes = "Disabled by default across clients so it does not load on every project; authenticates host-side with the SOPS-provisioned API key at `~/.local/share/google-developer-knowledge/api-key` (`X-Goog-Api-Key` from `secrets/google-developer-knowledge-mcp.yaml`). Enable without restarting via `mcp-codemode enable google-developer-knowledge` from the target project directory (writes a project-scoped entry in `~/.local/state/mcp-codemode/overrides.json` matching that directory and its subdirectories) or `mcp-codemode enable --user google-developer-knowledge` (required for GUI clients launched outside the open workspace), or launch the client with `MCP_CODEMODE_ENABLE=google-developer-knowledge`.";
        example = "`mcp-codemode enable google-developer-knowledge`";
      };
    };

    deepwiki = {
      source = "http";
      url = "https://mcp.deepwiki.com/mcp";
      clients = [
        "antigravity"
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Browse repository knowledge bases.";
        accessNotes = "Official remote no-authentication-required HTTP endpoint; pass `owner/repo` to the DeepWiki tools.";
        example = "Use `codemode` `search` (`await codemode.tools(\"deepwiki\")`).";
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
        "antigravity"
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Control and inspect a live Chrome browser session.";
        accessNotes = "Shared wrapper forces usage statistics and CrUX off and disables update checks and npm update notifications. Standalone `--` is rejected so required flags cannot become positional arguments. Runs the full tool set: every optional category (network mocks, extensions, WebMCP, third-party page tools, PWA, WebAuthn), the coordinate, memory, and DevTools-UI tools, and WebMCP enabled in Chrome. Needs Chrome 150 or newer for WebMCP. Managed clients use it instead of the upstream plugins. Browser traffic and npm package resolution remain enabled; these controls are not a network sandbox.";
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
        "antigravity"
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Control and inspect a live Camoufox (Firefox) session, including privileged contexts.";
        accessNotes = "Runs the Mozilla build of the server with every tool module, driving the camoufox app's browser, so it is present only where that app's row is on. Camoufox does not replace geckodriver, which still translates the server's WebDriver calls; the geckodriver app supplies it and the wrapper puts it on PATH. The wrapper sets MOZ_REMOTE_ALLOW_SYSTEM_ACCESS=1 for the privileged modules and turns off Selenium Manager statistics and the Firefox crash reporter; Firefox telemetry prefs are off. Each session uses a fresh temporary profile. The privileged modules give the agent browser-privileged access with no web-content sandbox, so it can act outside the page.";
        example = "Use `codemode` `search` (`await codemode.tools(\"firefox\")`).";
      };
    };

    sbx = {
      source = "app";
      app = "sbx";
      program = "sbx-mcp";
      direct = true;
      autoApprove = true;
      # A call lasts up to a sandbox's longest TTL; Codex stops waiting after 300 s by default.
      toolTimeout = cfg: cfg.limits.maxTtl * 3600;
      clients = [
        "antigravity"
        "claude"
        "codex"
      ];
      docs = {
        primaryUse = "Run untrusted code in disposable sbx VMs.";
        accessNotes = "Local stdio server of the `sbx` app, registered directly to preserve `_meta` session scoping, cancellation, and VM TTL timeouts; present only where its row is on.";
        example = "`run` with `{\"base\": \"nixos\", \"command\": [\"uname\", \"-a\"]}`";
      };
    };

    node_repl = {
      source = "app";
      app = "chatgpt";
      program = cfg: "${cfg.finalPackage.unwrapped}/lib/chatgpt/resources/cua_node/bin/node_repl";
      direct = true;
      timeout = 120;
      clients = [ "codex" ];
      docs = {
        primaryUse = "Run JavaScript in the ChatGPT browser runtime.";
        accessNotes = "Requires the ChatGPT desktop package; registered directly on Codex to preserve native browser confirmation routing and isolate desktop IPC environment variables.";
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
        "antigravity"
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
