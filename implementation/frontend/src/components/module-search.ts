/**
 * Module Search Web Component
 * Self-contained with inline styles and no external dependencies
 */

export class ModuleSearchComponent extends HTMLElement {
  private shadow: ShadowRoot;
  private debounceTimer: number | null = null;
  private currentRequest: AbortController | null = null;
  private readonly DEBOUNCE_MS = 300;
  private searchInput: HTMLInputElement | null = null;
  private resultsContainer: HTMLElement | null = null;
  private loadingIndicator: HTMLElement | null = null;

  constructor() {
    super();
    this.shadow = this.attachShadow({ mode: "open" });
  }

  connectedCallback() {
    this.render();
    this.setupEventListeners();
  }

  disconnectedCallback() {
    // Clean up timers and requests when component is removed
    if (this.debounceTimer !== null) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
    if (this.currentRequest) {
      this.currentRequest.abort();
      this.currentRequest = null;
    }
  }

  private render() {
    // Create styles using Constructable Stylesheets
    const sheet = new CSSStyleSheet();
    sheet.replaceSync(this.getStyles());
    this.shadow.adoptedStyleSheets = [sheet];

    // Create HTML structure
    this.shadow.innerHTML = `
      <div class="search-container">
        <div class="search-header">
          <h2>Search NixOS Modules</h2>
          <p>Find modules by name, description, or options</p>
        </div>

        <div class="search-input-wrapper">
          <input
            type="text"
            id="search-input"
            placeholder="e.g., networking, vim, systemd..."
            aria-label="Search modules"
            autocomplete="off"
          />
          <div class="search-icon" aria-hidden="true">
            <svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clip-rule="evenodd" />
            </svg>
          </div>
        </div>

        <div class="filters">
          <select id="namespace-filter" aria-label="Filter by namespace">
            <option value="">All namespaces</option>
            <option value="networking">Networking</option>
            <option value="services">Services</option>
            <option value="programs">Programs</option>
            <option value="system">System</option>
            <option value="hardware">Hardware</option>
          </select>

          <select id="type-filter" aria-label="Filter by type">
            <option value="">All types</option>
            <option value="nixos">NixOS</option>
            <option value="home-manager">Home Manager</option>
            <option value="flake-parts">Flake Parts</option>
          </select>
        </div>

        <div id="loading" class="loading hidden" aria-live="polite">
          <span class="spinner"></span>
          <span>Searching...</span>
        </div>

        <div id="results" class="results" aria-live="polite"></div>

        <div id="error" class="error hidden" role="alert"></div>
      </div>
    `;

    // Cache DOM references
    this.searchInput = this.shadow.querySelector("#search-input");
    this.resultsContainer = this.shadow.querySelector("#results");
    this.loadingIndicator = this.shadow.querySelector("#loading");
  }

  private getStyles(): string {
    return `
      :host {
        display: block;
        font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        color: #1f2937;
        line-height: 1.5;
      }

      * {
        box-sizing: border-box;
      }

      .search-container {
        max-width: 800px;
        margin: 0 auto;
        padding: 2rem;
      }

      .search-header {
        text-align: center;
        margin-bottom: 2rem;
      }

      .search-header h2 {
        font-size: 2rem;
        font-weight: 700;
        margin: 0 0 0.5rem 0;
        color: #111827;
      }

      .search-header p {
        color: #6b7280;
        margin: 0;
      }

      .search-input-wrapper {
        position: relative;
        margin-bottom: 1rem;
      }

      #search-input {
        width: 100%;
        padding: 0.75rem 1rem 0.75rem 3rem;
        font-size: 1rem;
        border: 2px solid #e5e7eb;
        border-radius: 0.5rem;
        transition: border-color 0.15s ease;
        background-color: white;
      }

      #search-input:focus {
        outline: none;
        border-color: #3b82f6;
        box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
      }

      .search-icon {
        position: absolute;
        left: 1rem;
        top: 50%;
        transform: translateY(-50%);
        color: #9ca3af;
        pointer-events: none;
      }

      .filters {
        display: flex;
        gap: 1rem;
        margin-bottom: 1.5rem;
      }

      select {
        flex: 1;
        padding: 0.5rem;
        border: 1px solid #e5e7eb;
        border-radius: 0.375rem;
        background-color: white;
        font-size: 0.875rem;
        color: #374151;
        cursor: pointer;
      }

      select:focus {
        outline: none;
        border-color: #3b82f6;
        box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
      }

      .loading {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 0.5rem;
        padding: 2rem;
        color: #6b7280;
      }

      .loading.hidden {
        display: none;
      }

      .spinner {
        width: 1.25rem;
        height: 1.25rem;
        border: 2px solid #e5e7eb;
        border-top-color: #3b82f6;
        border-radius: 50%;
        animation: spin 0.6s linear infinite;
      }

      @keyframes spin {
        to { transform: rotate(360deg); }
      }

      .results {
        min-height: 100px;
      }

      .result-item {
        padding: 1rem;
        margin-bottom: 0.75rem;
        background-color: white;
        border: 1px solid #e5e7eb;
        border-radius: 0.5rem;
        transition: all 0.15s ease;
        cursor: pointer;
      }

      .result-item:hover {
        border-color: #3b82f6;
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
      }

      .result-header {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        margin-bottom: 0.5rem;
      }

      .result-name {
        font-weight: 600;
        color: #1f2937;
        font-size: 1.125rem;
      }

      .result-type {
        display: inline-block;
        padding: 0.125rem 0.5rem;
        background-color: #eff6ff;
        color: #1e40af;
        border-radius: 0.25rem;
        font-size: 0.75rem;
        font-weight: 500;
        text-transform: uppercase;
      }

      .result-description {
        color: #4b5563;
        font-size: 0.875rem;
        margin-bottom: 0.5rem;
        line-height: 1.5;
      }

      .result-meta {
        display: flex;
        gap: 1rem;
        font-size: 0.75rem;
        color: #9ca3af;
      }

      .result-meta-item {
        display: flex;
        align-items: center;
        gap: 0.25rem;
      }

      .error {
        padding: 1rem;
        background-color: #fef2f2;
        border: 1px solid #fecaca;
        border-radius: 0.5rem;
        color: #b91c1c;
        margin-top: 1rem;
      }

      .error.hidden {
        display: none;
      }

      .no-results {
        text-align: center;
        padding: 3rem 1rem;
        color: #6b7280;
      }

      .no-results h3 {
        font-size: 1.25rem;
        margin: 0 0 0.5rem 0;
        color: #374151;
      }

      @media (max-width: 640px) {
        .search-container {
          padding: 1rem;
        }

        .filters {
          flex-direction: column;
        }

        .search-header h2 {
          font-size: 1.5rem;
        }
      }
    `;
  }

  private setupEventListeners() {
    // Search input handler
    this.searchInput?.addEventListener("input", (e) => {
      const target = e.target as HTMLInputElement;
      this.handleSearch(target.value);
    });

    // Filter change handlers
    const namespaceFilter = this.shadow.querySelector("#namespace-filter");
    const typeFilter = this.shadow.querySelector("#type-filter");

    namespaceFilter?.addEventListener("change", () => {
      if (this.searchInput?.value) {
        this.handleSearch(this.searchInput.value);
      }
    });

    typeFilter?.addEventListener("change", () => {
      if (this.searchInput?.value) {
        this.handleSearch(this.searchInput.value);
      }
    });

    // Result click handlers (using event delegation)
    this.resultsContainer?.addEventListener("click", (e) => {
      const resultItem = (e.target as HTMLElement).closest(".result-item");
      if (resultItem) {
        const moduleName = resultItem.getAttribute("data-module-name");
        if (moduleName) {
          this.handleModuleClick(moduleName);
        }
      }
    });
  }

  private handleSearch(query: string) {
    // Cancel any pending requests
    if (this.currentRequest) {
      this.currentRequest.abort();
      this.currentRequest = null;
    }

    // Clear existing timer
    if (this.debounceTimer !== null) {
      clearTimeout(this.debounceTimer);
    }

    if (query.length < 2) {
      this.clearResults();
      return;
    }

    // Set up new debounced search
    this.debounceTimer = setTimeout(() => {
      this.performSearch(query);
    }, this.DEBOUNCE_MS);
  }

  private async performSearch(query: string) {
    // Create new abort controller for this request
    this.currentRequest = new AbortController();

    // Show loading state
    this.showLoading();

    try {
      // Build query parameters
      const params = new URLSearchParams({
        q: query,
        limit: "20",
      });

      // Add filters if selected
      const namespaceFilter = this.shadow.querySelector(
        "#namespace-filter",
      ) as HTMLSelectElement;
      const typeFilter = this.shadow.querySelector(
        "#type-filter",
      ) as HTMLSelectElement;

      if (namespaceFilter?.value) {
        params.set("namespace", namespaceFilter.value);
      }

      if (typeFilter?.value) {
        params.set("type", typeFilter.value);
      }

      const response = await fetch(`/api/v1/search?${params}`, {
        signal: this.currentRequest.signal,
        headers: {
          Accept: "application/json",
        },
      });

      if (!response.ok) {
        throw new Error(`Search failed: ${response.status}`);
      }

      const data = await response.json();
      this.displayResults(data.modules || []);
    } catch (error) {
      if ((error as Error).name === "AbortError") {
        // Request was cancelled, ignore
        return;
      }
      console.error("Search error:", error);
      this.displayError("Search failed. Please try again.");
    } finally {
      this.hideLoading();
      this.currentRequest = null;
    }
  }

  private displayResults(modules: any[]) {
    if (!this.resultsContainer) return;

    if (modules.length === 0) {
      this.resultsContainer.innerHTML = `
        <div class="no-results">
          <h3>No modules found</h3>
          <p>Try adjusting your search terms or filters</p>
        </div>
      `;
      return;
    }

    const resultsHTML = modules
      .map(
        (module) => `
      <div class="result-item" data-module-name="${this.escapeHtml(module.name)}">
        <div class="result-header">
          <span class="result-name">${this.escapeHtml(module.name)}</span>
          <span class="result-type">${this.escapeHtml(module.type || "nixos")}</span>
        </div>
        <div class="result-description">
          ${this.escapeHtml(module.description || "No description available")}
        </div>
        <div class="result-meta">
          <span class="result-meta-item">
            <span>📁</span>
            <span>${this.escapeHtml(module.namespace || "default")}</span>
          </span>
          ${
            module.optionCount
              ? `
            <span class="result-meta-item">
              <span>⚙️</span>
              <span>${module.optionCount} options</span>
            </span>
          `
              : ""
          }
        </div>
      </div>
    `,
      )
      .join("");

    this.resultsContainer.innerHTML = resultsHTML;
  }

  private handleModuleClick(moduleName: string) {
    // Dispatch custom event for module selection
    this.dispatchEvent(
      new CustomEvent("module-selected", {
        detail: { moduleName },
        bubbles: true,
        composed: true,
      }),
    );
  }

  private clearResults() {
    if (this.resultsContainer) {
      this.resultsContainer.innerHTML = "";
    }
  }

  private showLoading() {
    this.loadingIndicator?.classList.remove("hidden");
    this.clearResults();
  }

  private hideLoading() {
    this.loadingIndicator?.classList.add("hidden");
  }

  private displayError(message: string) {
    const errorEl = this.shadow.querySelector("#error");
    if (errorEl) {
      errorEl.textContent = message;
      errorEl.classList.remove("hidden");
      setTimeout(() => {
        errorEl.classList.add("hidden");
      }, 5000);
    }
  }

  private escapeHtml(text: string): string {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }
}

// Register the custom element
customElements.define("module-search", ModuleSearchComponent);
