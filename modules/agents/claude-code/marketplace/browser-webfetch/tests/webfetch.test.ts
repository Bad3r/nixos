import { expect, test, type TestBody } from "claude-code/testing";

const COMMAND = "/nix/store/x-browser-fetch/bin/browser-fetch";
const OPTIONS = { options: { fetchCommand: COMMAND } };
const USAGE = {
	input_tokens: 1,
	output_tokens: 1,
	cache_read_input_tokens: 0,
	cache_creation_input_tokens: 0,
};
const QUOTE_ASK = `Provide a concise response based only on the content above. In your response:
 - Enforce a strict 125-character maximum for quotes from any source document. Open Source Software is ok as long as we respect the license.
 - Use quotation marks for exact language from articles; any language outside of the quotation should never be word-for-word the same.
 - You are not a lawyer and never comment on the legality of your own prompts and responses.
 - Never produce or reproduce exact song lyrics.`;
const FETCH_FAILED = "Request to the WebFetch proxy failed (transport error).";
const BACKEND = /browser|camoufox|curl|cookie|\/nix\/store/i;
const DOCS_ASK =
	"Provide a concise response based on the content above. Include relevant details, code examples, and documentation excerpts as needed.";

type Record = {
	outcome: "ok" | "redirect" | "http_error";
	status: number;
	statusText: string;
	contentType: string;
	bytes: number;
	binary: boolean;
	preapproved: boolean;
	length: number;
	text: string;
	via?: string;
	reason?: string;
	redirectFrom?: string;
	redirectTo?: string;
	retryAfter?: string;
	savedPath?: string;
	savedBytes?: number;
};
type Ran = { exitCode: number; stdout?: string; stderr?: string };
type Answer =
	| { text: string }
	| { reason: "api-error" | "empty-reply" | "aborted" };
type Seen = { argvs: unknown[]; asks: { model: string; prompt: string }[] };

function page(fields: Partial<Record>): Record {
	const text = fields.text ?? "Hello page.";
	return {
		outcome: "ok",
		status: 200,
		statusText: "OK",
		contentType: "text/html; charset=utf-8",
		bytes: 1234,
		binary: false,
		preapproved: false,
		length: text.length,
		text,
		via: "curl",
		...fields,
	};
}

function engine(
	on: Parameters<TestBody>[1],
	ran: Ran,
	answer: Answer = { text: "The answer." },
): Seen {
	const seen: Seen = { argvs: [], asks: [] };
	on("process.run", (_, e) => {
		seen.argvs.push(e.argv);
		return {
			value: {
				stdout: "",
				stderr: "",
				isStdoutTruncated: false,
				isStderrTruncated: false,
				...ran,
			},
		};
	});
	on("model.complete", (_, e) => {
		seen.asks.push({ model: e.model, prompt: e.prompt });
		if ("text" in answer) {
			return { value: { isAnswered: true, text: answer.text, usage: USAGE } };
		}
		if (answer.reason === "api-error") {
			return {
				value: {
					isAnswered: false as const,
					reason: "api-error" as const,
					status: 529,
					error: "overloaded" as const,
					usage: USAGE,
				},
			};
		}
		return {
			value: {
				isAnswered: false as const,
				reason: answer.reason,
				usage: USAGE,
			},
		};
	});
	return seen;
}

function ok(record: Record): Ran {
	return { exitCode: 0, stdout: JSON.stringify(record) };
}

const fetch = (url: string, prompt: string, offset?: number) => ({
	tool: "WebFetch" as const,
	url,
	prompt,
	...(offset === undefined ? {} : { offset }),
});

test(
	"a page is answered by haiku with the built-in prompt",
	OPTIONS,
	async ($, on) => {
		const seen = engine(on, ok(page({})));
		const answer = await $.tool.call(
			fetch("https://example.org/a", "What does it say?"),
		);
		expect(seen.argvs).toEqual([
			[
				COMMAND,
				"--json",
				"--offset",
				"0",
				"--max-chars",
				"100001",
				"--deadline",
				"240",
				"--",
				"https://example.org/a",
			],
		]);
		expect(seen.asks).toEqual([
			{
				model: "haiku",
				prompt: `\nWeb page content:\n---\nHello page.\n---\n\nWhat does it say?\n\n${QUOTE_ASK}\n`,
			},
		]);
		expect(answer.result).toEqual({
			bytes: 1234,
			code: 200,
			codeText: "OK",
			result: "The answer.",
			durationMs: expect.any(Number),
			url: "https://example.org/a",
		});
	},
);

test(
	"a preapproved page gets the documentation prompt",
	OPTIONS,
	async ($, on) => {
		const seen = engine(on, ok(page({ preapproved: true })));
		await $.tool.call(fetch("https://docs.python.org/3/", "Summarize"));
		expect(seen.asks[0]?.prompt).toBe(
			`\nWeb page content:\n---\nHello page.\n---\n\nSummarize\n\n${DOCS_ASK}\n`,
		);
	},
);

test(
	"a page past the cap is cut and the result says where to read on",
	OPTIONS,
	async ($, on) => {
		const text = "a".repeat(100_001);
		const seen = engine(on, ok(page({ text, length: 150_000 })));
		const answer = await $.tool.call(fetch("https://example.org/", "q"));
		const prompt = seen.asks[0]?.prompt ?? "";
		expect(prompt).toContain(
			`---\n${"a".repeat(100_000)}\n\n[Content truncated due to length...]\n---`,
		);
		expect(answer.result).toEqual(
			expect.objectContaining({
				result:
					"The answer.\n\n[WebFetch note: this page's text is 150000 characters long and the answer above covers only characters 0 to 100000; the final 50000 were not read — to read on, call WebFetch again with the same url and offset: 100000.]",
			}),
		);
	},
);

test(
	"an offset reads on from there and says so to the model",
	OPTIONS,
	async ($, on) => {
		const seen = engine(on, ok(page({ text: "tail text", length: 100_009 })));
		const answer = await $.tool.call(
			fetch("https://example.org/", "q", 100_000),
		);
		expect(seen.argvs[0]).toEqual(
			expect.arrayContaining(["--offset", "100000"]),
		);
		expect(seen.asks[0]?.prompt).toBe(
			`The content below is one part of a longer page: it starts 100000 characters into the page's 100009.\n\nWeb page content:\n---\ntail text\n---\n\nq\n\n${QUOTE_ASK}\n`,
		);
		expect(answer.result).toEqual(
			expect.objectContaining({ result: "The answer." }),
		);
	},
);

test(
	"an offset that starts inside a surrogate pair drops its low half",
	OPTIONS,
	async ($, on) => {
		const seen = engine(on, ok(page({ text: "\udc00rest", length: 10 })));
		await $.tool.call(fetch("https://example.org/", "q", 5));
		expect(seen.asks[0]?.prompt).toContain("---\nrest\n---");
	},
);

test("an offset past the end needs no model call", OPTIONS, async ($, on) => {
	const seen = engine(on, ok(page({ text: "", length: 42 })));
	const answer = await $.tool.call(fetch("https://example.org/", "q", 50));
	expect(seen.asks).toEqual([]);
	expect(answer.result).toEqual(
		expect.objectContaining({
			result:
				"Nothing left to read from offset 50: this page's text is 42 characters long.",
		}),
	);
});

test(
	"preapproved Markdown under the cap is returned as it is",
	OPTIONS,
	async ($, on) => {
		const seen = engine(
			on,
			ok(
				page({
					preapproved: true,
					contentType: "text/markdown",
					text: "# Doc",
				}),
			),
		);
		const answer = await $.tool.call(
			fetch("https://code.claude.com/x.md", "q"),
		);
		expect(seen.asks).toEqual([]);
		expect(answer.result).toEqual(expect.objectContaining({ result: "# Doc" }));
	},
);

test(
	"an HTTP error is reported as the built-in reports it",
	OPTIONS,
	async ($, on) => {
		const seen = engine(
			on,
			ok(
				page({
					outcome: "http_error",
					status: 429,
					statusText: "Too Many Requests",
					retryAfter: "30",
					text: "",
					length: 0,
				}),
			),
		);
		const answer = await $.tool.call(fetch("https://example.org/", "q"));
		expect(seen.asks).toEqual([]);
		expect(answer.result).toEqual({
			bytes: 0,
			code: 429,
			codeText: "Too Many Requests",
			result:
				"The server returned HTTP 429 Too Many Requests.\nRetry-After: 30\n\nThe response body was not retrieved. If this URL requires authentication, use an authenticated tool (e.g. `gh` for GitHub, or an MCP-provided fetch tool) instead of WebFetch.",
			durationMs: expect.any(Number),
			url: "https://example.org/",
		});
	},
);

test(
	"a redirect to another host is reported, not followed",
	OPTIONS,
	async ($, on) => {
		engine(
			on,
			ok(
				page({
					outcome: "redirect",
					status: 301,
					statusText: "Moved Permanently",
					redirectFrom: "https://example.org/old",
					redirectTo: "https://other.example/new?x=1",
					text: "",
					length: 0,
				}),
			),
		);
		const answer = await $.tool.call(
			fetch("http://example.org/old", "Find X", 7),
		);
		const result = `REDIRECT DETECTED: The URL redirects to a location that was not fetched automatically.

    Original URL: https://example.org/old
    Redirect URL (from the server's Location header — server-supplied, not verified): https://other.example/new?x=1
    Status: 301 Moved Permanently

    To complete your request, I need to fetch content from the redirected URL. Please use WebFetch again with these parameters:
    - url: "https://other.example/new?x=1"
    - prompt: "Find X"
    - offset: 7`;
		expect(answer.result).toEqual({
			bytes: new TextEncoder().encode(result).length,
			code: 301,
			codeText: "Moved Permanently",
			result,
			durationMs: expect.any(Number),
			url: "http://example.org/old",
		});
	},
);

test(
	"a challenge the browser could not clear is an HTTP error",
	OPTIONS,
	async ($, on) => {
		// The record browser-fetch prints when the browser ends on a 403.
		const seen = engine(
			on,
			ok(
				page({
					outcome: "http_error",
					status: 403,
					statusText: "Forbidden",
					contentType: "",
					bytes: 0,
					via: "browser",
					reason: "a Cloudflare challenge",
					text: "",
					length: 0,
				}),
			),
		);
		const answer = await $.tool.call(fetch("https://example.org/", "q"));
		expect(seen.asks).toEqual([]);
		expect(answer.deny).toBeUndefined();
		expect(answer.result).toEqual({
			bytes: 0,
			code: 403,
			codeText: "Forbidden",
			result:
				"The server returned HTTP 403 Forbidden.\n\nThe response body was not retrieved. If this URL requires authentication, use an authenticated tool (e.g. `gh` for GitHub, or an MCP-provided fetch tool) instead of WebFetch.",
			durationMs: expect.any(Number),
			url: "https://example.org/",
		});
	},
);

test(
	"a binary document names the file it was saved to",
	OPTIONS,
	async ($, on) => {
		engine(
			on,
			ok(
				page({
					contentType: "application/pdf",
					binary: true,
					bytes: 2_621_440,
					savedPath: "/home/u/.cache/browser-fetch/webfetch-1-abc.pdf",
					savedBytes: 2_621_440,
				}),
			),
		);
		const answer = await $.tool.call(fetch("https://example.org/a.pdf", "q"));
		expect(answer.result).toEqual(
			expect.objectContaining({
				result:
					"The answer.\n\n[Binary content (application/pdf, 2.5MB) also saved to /home/u/.cache/browser-fetch/webfetch-1-abc.pdf]",
			}),
		);
	},
);

for (const [exitCode, stderr] of [
	[4, "request to https://example.org/ failed: the request timed out"],
	[
		3,
		"the cookie database /home/u/.local/state/browser-fetch/profile/cookies.sqlite has schema version 18, not 17; browser-fetch neither reads nor writes it",
	],
	[5, "the browser failed: Camoufox crashed"],
] as const) {
	test(
		`exit ${exitCode} is the built-in's proxy failure, with no backend detail`,
		OPTIONS,
		async ($, on) => {
			engine(on, { exitCode, stderr: `browser-fetch: ${stderr}\n` });
			const answer = await $.tool.call(fetch("https://example.org/", "q"));
			expect(answer.deny).toBe(FETCH_FAILED);
			expect(answer.deny).not.toMatch(BACKEND);
		},
	);
}

test(
	"a warning line before the error leaves the error as the reason",
	OPTIONS,
	async ($, on) => {
		engine(on, {
			exitCode: 4,
			stderr:
				"browser-fetch: warning: 1 cookie changes were not saved: busy\nbrowser-fetch: Too many redirects (exceeded 10)\n",
		});
		const answer = await $.tool.call(fetch("https://example.org/", "q"));
		expect(answer.deny).toBe("Too many redirects (exceeded 10)");
	},
);

for (const reason of [
	"Invalid URL",
	"WebFetch cannot fetch localhost or other hostnames without a dot. To reach a local server, use Bash with curl instead.",
	"Too many redirects (exceeded 10)",
]) {
	test(
		`the built-in's own "${reason.slice(0, 24)}" reaches the model as written`,
		OPTIONS,
		async ($, on) => {
			engine(on, { exitCode: 2, stderr: `browser-fetch: ${reason}\n` });
			const answer = await $.tool.call(fetch("https://example.org/", "q"));
			expect(answer.deny).toBe(reason);
		},
	);
}

test(
	"output that is no page record is the built-in's proxy failure",
	OPTIONS,
	async ($, on) => {
		engine(on, { exitCode: 0, stdout: "<html>" });
		const answer = await $.tool.call(fetch("https://example.org/", "q"));
		expect(answer.deny).toBe(FETCH_FAILED);
	},
);

test(
	"a model call that fails is refused with the built-in's text",
	OPTIONS,
	async ($, on) => {
		engine(on, ok(page({})), { reason: "api-error" });
		const answer = await $.tool.call(fetch("https://example.org/", "q"));
		expect(answer.deny).toBe(FETCH_FAILED);
	},
);

test(
	"an aborted model call is refused with the built-in's text",
	OPTIONS,
	async ($, on) => {
		engine(on, ok(page({})), { reason: "aborted" });
		const answer = await $.tool.call(fetch("https://example.org/", "q"));
		expect(answer.deny).toBe(FETCH_FAILED);
		expect(answer.deny).not.toMatch(/secondary|model call/);
	},
);

test("an empty reply reads as the built-in's", OPTIONS, async ($, on) => {
	engine(on, ok(page({})), { reason: "empty-reply" });
	const answer = await $.tool.call(fetch("https://example.org/", "q"));
	expect(answer.result).toEqual(
		expect.objectContaining({ result: "No response from model" }),
	);
});

test(
	"an unset fetchCommand is the built-in's proxy failure without running anything",
	{ options: { fetchCommand: "" } },
	async ($, on) => {
		const seen = engine(on, { exitCode: 0 });
		const answer = await $.tool.call(fetch("https://example.org/", "q"));
		expect(answer.deny).toBe(FETCH_FAILED);
		expect(seen.argvs).toEqual([]);
	},
);
