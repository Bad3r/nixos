import type { Register } from "claude-code";

// Claude Code 2.1.319's WebFetch, from its tool module: the cap on the text
// the secondary model reads, and the prompt it uses for a site it does not
// preapprove.
const CAP = 100_000;
const TRUNCATED = "\n\n[Content truncated due to length...]";
const QUOTE_RULES = ` - Enforce a strict 125-character maximum for quotes from any source document. Open Source Software is ok as long as we respect the license.
 - Use quotation marks for exact language from articles; any language outside of the quotation should never be word-for-word the same.
 - You are not a lawyer and never comment on the legality of your own prompts and responses.
 - Never produce or reproduce exact song lyrics.`;
const OTHER_ASK = `Provide a concise response based only on the content above. In your response:\n${QUOTE_RULES}`;
const FETCH_TIMEOUT_MS = 300_000;
// browser-fetch's own deadline, inside the timeout with room to clean up.
const FETCH_DEADLINE_S = 240;
const MODEL_TIMEOUT_MS = 240_000;
const MAX_TOKENS = 64_000;
// The built-in's own failure texts, which browser-fetch writes for these cases.
const BUILTIN_REASONS = new Set([
	"Invalid URL",
	"Too many redirects (exceeded 10)",
]);
// What Claude Code 2.1.319 tells the model when its fetch proxy fails
// (PROXY_TRANSPORT); every other failure reads as this.
const FETCH_FAILED = "Request to the WebFetch proxy failed (transport error).";

type Page = {
	outcome: "ok" | "redirect" | "http_error";
	status: number;
	statusText: string;
	contentType: string;
	bytes: number;
	binary: boolean;
	length: number;
	text: string;
	redirectFrom?: string;
	redirectTo?: string;
	retryAfter?: string;
	savedPath?: string;
	savedBytes?: number;
	// What the fetch could not do, such as save a cookie change.
	warnings?: string[];
};

function isPage(value: unknown): value is Page {
	if (typeof value !== "object" || value === null) return false;
	const page = value as Record<string, unknown>;
	return (
		["ok", "redirect", "http_error"].includes(page.outcome as string) &&
		typeof page.status === "number" &&
		typeof page.statusText === "string" &&
		typeof page.contentType === "string" &&
		typeof page.bytes === "number" &&
		typeof page.length === "number" &&
		typeof page.text === "string"
	);
}

// browser-fetch's warnings, one note each, for the model to weigh.
function warned(warnings: readonly unknown[]): string {
	return warnings
		.filter((w): w is string => typeof w === "string" && w !== "")
		.map((w) => `\n\n[WebFetch warning: ${w}]`)
		.join("");
}

const WARNING = "browser-fetch: warning: ";

function pageOf(stdout: string): Page | undefined {
	try {
		const parsed: unknown = JSON.parse(stdout);
		return isPage(parsed) ? parsed : undefined;
	} catch {
		return undefined;
	}
}

const isHigh = (code: number) => code >= 0xd800 && code <= 0xdbff;
const isLow = (code: number) => code >= 0xdc00 && code <= 0xdfff;

// The first n code units, never ending inside a surrogate pair.
function head(text: string, n: number): string {
	if (n <= 0) return "";
	if (text.length <= n) return text;
	const cut = text.slice(0, n);
	return isHigh(cut.charCodeAt(n - 1)) ? cut.slice(0, -1) : cut;
}

// Kilobytes as Claude Code writes a saved file's size.
function size(bytes: number): string {
	const kb = bytes / 1024;
	if (kb < 1) return `${bytes} bytes`;
	const fixed = (n: number) => n.toFixed(1).replace(/\.0$/, "");
	if (kb < 1024) return `${fixed(kb)}KB`;
	const mb = kb / 1024;
	return mb < 1024 ? `${fixed(mb)}MB` : `${fixed(mb / 1024)}GB`;
}

function mediaType(contentType: string): string {
	return (
		/^[\w!#$&^.+-]{1,64}\/[\w!#$&^.+-]{1,64}/.exec(contentType)?.[0] ??
		"unknown content type"
	);
}

function askFor(content: string, prompt: string): string {
	return `\nWeb page content:\n---\n${content}\n---\n\n${prompt}\n\n${OTHER_ASK}\n`;
}

function httpError(page: Page): string {
	const retry = page.retryAfter ? `\nRetry-After: ${page.retryAfter}` : "";
	return `The server returned HTTP ${page.status} ${page.statusText}.${retry}

The response body was not retrieved. If this URL requires authentication, use an authenticated tool (e.g. \`gh\` for GitHub, or an MCP-provided fetch tool) instead of WebFetch.`;
}

function redirect(page: Page, prompt: string, offset: number): string {
	const location = page.redirectTo ?? "";
	const target = URL.canParse(location) ? new URL(location) : null;
	const web =
		target !== null &&
		(target.protocol === "https:" || target.protocol === "http:");
	const full = web
		? `${target.origin}${target.pathname}${target.search}${target.hash}`
		: "";
	const shown = web ? head(full, 1000) : undefined;
	const withheld = full.length - (shown?.length ?? 0);
	const longHost = web && target.hostname.length > 255;
	const line =
		shown === undefined
			? "Redirect URL: (withheld — the server sent a redirect target that is not a valid http(s) URL)"
			: `Redirect URL (from the server's Location header — server-supplied, not verified): ${shown}${withheld > 0 ? ` […${withheld} more characters withheld: too long to relay]` : ""}${longHost ? " [hostname longer than any DNS name (255 characters): not a fetchable address]" : ""}`;
	const relayed = shown !== undefined && withheld === 0 && !longHost;
	const next = relayed
		? `To complete your request, I need to fetch content from the redirected URL. Please use WebFetch again with these parameters:
    - url: "${shown}"
    - prompt: "${prompt}"${offset > 0 ? `\n    - offset: ${offset}` : ""}`
		: "The redirect target could not be relayed in full or is not a fetchable address, so it cannot be fetched from here; report the redirect instead.";
	return `REDIRECT DETECTED: The URL redirects to a location that was not fetched automatically.

    Original URL: ${page.redirectFrom ?? ""}
    ${line}
    Status: ${page.status} ${page.statusText}

    ${next}`;
}

export const register: Register = (on, options) => {
	const command =
		typeof options.fetchCommand === "string" ? options.fetchCommand : "";

	// Answers WebFetch before Claude Code's permission check runs.
	on("tool.call", { tool: "WebFetch" }, async ($, e) => {
		$.ui.status(undefined);
		// The reason goes to the status line; the model gets the built-in's
		// text and the fetch's warnings.
		let warnings = "";
		const fail = (reason: string, told = FETCH_FAILED) => {
			$.ui.status(`WebFetch failed: ${reason.slice(0, 60)}`);
			return { deny: told + warnings };
		};
		if (!command) return fail("the fetchCommand option is not set");
		const offset = e.offset ?? 0;
		const started = Date.now();
		const argv = [
			command,
			"--json",
			"--offset",
			String(offset),
			"--max-chars",
			// One more than the cap, for a window that loses a split low surrogate.
			String(CAP + 1),
			"--deadline",
			String(FETCH_DEADLINE_S),
			"--",
			e.url,
		];
		const ran = await $.process
			.run(argv, { timeoutMs: FETCH_TIMEOUT_MS })
			.catch((error: Error) => error);
		if (ran instanceof Error) {
			return fail(`${command} did not finish: ${ran.message}`);
		}
		if (ran.exitCode !== 0) {
			// The last line is the error; warning lines may come before it.
			const lines = ran.stderr.trim().split("\n");
			warnings = warned(
				lines
					.filter((line) => line.startsWith(WARNING))
					.map((line) => line.slice(WARNING.length)),
			);
			const last = lines.at(-1) ?? "";
			const reason = last.replace(/^browser-fetch: /, "");
			return BUILTIN_REASONS.has(reason)
				? fail(reason, reason)
				: fail(reason || `${command} exited ${ran.exitCode}`);
		}
		const page = pageOf(ran.stdout);
		if (!page) return fail(`${command} printed no page record`);
		warnings = warned(Array.isArray(page.warnings) ? page.warnings : []);
		const done = (result: string, bytes: number) => {
			$.ui.status(undefined);
			return {
				result: {
					bytes,
					code: page.status,
					codeText: page.statusText,
					result: result + warnings,
					durationMs: Date.now() - started,
					url: e.url,
				},
			};
		};

		if (page.outcome === "http_error") return done(httpError(page), 0);
		if (page.outcome === "redirect") {
			const text = redirect(page, e.prompt, offset);
			return done(text, new TextEncoder().encode(text).length);
		}

		// The text from offset on, as WebFetch slices it: a low surrogate
		// left over from a split pair is dropped.
		const dropped =
			offset > 0 && offset < page.length && isLow(page.text.charCodeAt(0))
				? 1
				: 0;
		const window = page.text.slice(dropped);
		const from = Math.min(offset, page.length) + dropped;
		const rest = Math.max(0, page.length - from);
		const saved = page.savedPath
			? `\n\n[Binary content (${mediaType(page.contentType)}, ${size(page.savedBytes ?? page.bytes)}) also saved to ${page.savedPath}]`
			: "";

		if (offset > 0 && rest === 0) {
			return done(
				`Nothing left to read from offset ${offset}: this page's text is ${page.length} characters long.${saved}`,
				page.bytes,
			);
		}

		const shown = head(window, CAP);
		const content = rest > CAP ? shown + TRUNCATED : window;
		const lead =
			offset > 0
				? `The content below is one part of a longer page: it starts ${offset} characters into the page's ${page.length}.\n`
				: "";
		const answer = await $.model.complete({
			model: "haiku",
			prompt: lead + askFor(content, e.prompt),
			maxTokens: MAX_TOKENS,
			timeoutMs: MODEL_TIMEOUT_MS,
		});
		if (!answer.isAnswered && answer.reason !== "empty-reply") {
			// The API's own error text is not exposed, so the model reads the
			// built-in's proxy failure and the status line gets the reason.
			return fail(
				answer.reason === "api-error"
					? `the secondary model call failed (HTTP ${answer.status} ${answer.error})`
					: `the secondary model call was ${answer.reason}`,
			);
		}
		let result =
			answer.isAnswered && answer.text ? answer.text : "No response from model";
		const covered = from + shown.length;
		if (covered < page.length && !page.binary) {
			result += `\n\n[WebFetch note: this page's text is ${page.length} characters long and the answer above covers only characters ${from} to ${covered}; the final ${page.length - covered} were not read — to read on, call WebFetch again with the same url and offset: ${covered}.]`;
		}
		return done(result + saved, page.bytes);
	}).catch(($) => {
		$.ui.status("WebFetch failed: the plugin's hook threw");
		return { deny: FETCH_FAILED };
	});
};
