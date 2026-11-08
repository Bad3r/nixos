import type { EngineInterface, Register } from "claude-code";

type Hit = { title: string; url: string; snippet: string };

// Claude Code 2.1.319's own nested search request: system prompt and message.
const SYSTEM =
	"You run a web search for another Claude model, which is waiting on the result and can search again. Search once, then reply with a brief summary of the results.";
const ASK = "Perform a web search for the query: ";
const ID_ALPHABET =
	"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
const ID_LENGTH = 33;
// Bytes from here up would favor the alphabet's first characters.
const UNBIASED_BYTES = 256 - (256 % ID_ALPHABET.length);

function isHit(value: unknown): value is Hit {
	if (typeof value !== "object" || value === null) return false;
	const { title, url, snippet } = value as Record<string, unknown>;
	return (
		typeof title === "string" &&
		typeof url === "string" &&
		typeof snippet === "string"
	);
}

function hitsOf(stdout: string): Hit[] | undefined {
	try {
		const parsed: unknown = JSON.parse(stdout);
		const hits = (parsed as { hits?: unknown }).hits;
		return Array.isArray(hits) && hits.every(isHit) ? hits : undefined;
	} catch {
		return undefined;
	}
}

// Shaped like the server tool ids the built-in tool records.
function serverToolUseId(): string {
	let id = "srvtoolu_01";
	while (id.length < ID_LENGTH) {
		for (const byte of crypto.getRandomValues(new Uint8Array(32))) {
			if (byte < UNBIASED_BYTES && id.length < ID_LENGTH) {
				id += ID_ALPHABET[byte % ID_ALPHABET.length];
			}
		}
	}
	return id;
}

function searchResults(query: string, hits: Hit[]): string {
	const listed = hits
		.map((hit, index) =>
			[`${index + 1}. ${hit.title}`, hit.url, hit.snippet]
				.filter(Boolean)
				.join("\n"),
		)
		.join("\n\n");
	return `${ASK}${query}\n\n<search_results>\n${listed}\n</search_results>`;
}

// What Claude Code 2.1.319 records when Anthropic's search reports an error (`Li()`).
function searchError(query: string, started: number) {
	return {
		result: {
			query,
			results: ["Web search error: unavailable"],
			durationSeconds: (Date.now() - started) / 1000,
			searchCount: 1,
		},
	};
}

// The person sees the reason; the model gets the built-in error record.
function failed(
	$: Pick<EngineInterface, "ui">,
	query: string,
	started: number,
	reason: string,
) {
	$.ui.status(`Kagi search failed: ${reason.slice(0, 60)}`);
	return searchError(query, started);
}

export const register: Register = (on, options) => {
	const command =
		typeof options.searchCommand === "string" ? options.searchCommand : "";
	const maxResults =
		typeof options.maxResults === "number" && options.maxResults > 0
			? Math.floor(options.maxResults)
			: 10;

	on("tool.call", { tool: "WebSearch" }, async ($, e) => {
		const started = Date.now();
		const fail = (reason: string) => failed($, e.query, started, reason);
		if (!command) return fail("the searchCommand option is not set");
		const argv = [command, "--json", "--limit", String(maxResults)];
		for (const domain of e.allowed_domains ?? []) argv.push("--allow", domain);
		for (const domain of e.blocked_domains ?? []) argv.push("--block", domain);
		argv.push("--", e.query);

		const ran = await $.process
			.run(argv, { timeoutMs: 60_000 })
			.catch((error: Error) => error);
		if (ran instanceof Error) {
			return fail(`${command} did not run: ${ran.message}`);
		}
		if (ran.exitCode !== 0) {
			const reason = ran.stderr.trim().replace(/^kagi-search: /, "");
			return fail(reason || `${command} exited ${ran.exitCode}`);
		}
		const hits = hitsOf(ran.stdout);
		if (!hits) return fail(`${command} printed no JSON hits`);

		// As the built-in tool records it: links without page text, then the
		// summary the session's model writes, when it writes one.
		const results: (
			| { tool_use_id: string; content: { title: string; url: string }[] }
			| string
		)[] = [
			{
				tool_use_id: serverToolUseId(),
				content: hits.map(({ title, url }) => ({ title, url })),
			},
		];
		if (hits.length > 0) {
			// A summary that cannot be had still leaves the links.
			const summary = await $.session
				.model()
				.then((model) =>
					$.model.complete({
						model,
						system: SYSTEM,
						prompt: searchResults(e.query, hits),
						maxTokens: 4096,
						effort: "low",
						timeoutMs: 120_000,
					}),
				)
				.catch(() => undefined);
			if (summary?.isAnswered && summary.text.trim()) {
				results.push(summary.text.trim());
			}
		}

		$.ui.status(undefined);
		return {
			result: {
				query: e.query,
				results,
				durationSeconds: (Date.now() - started) / 1000,
				searchCount: 1,
			},
		};
	}).catch(($, e, next) =>
		failed($, e.query, Date.now(), next.error.message ?? next.error.kind),
	);
};
