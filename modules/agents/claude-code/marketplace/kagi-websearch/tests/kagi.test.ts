import { expect, test, type TestBody } from "claude-code/testing";

const COMMAND = "/nix/store/x-kagi-search/bin/kagi-search";
const OPTIONS = { options: { searchCommand: COMMAND } };
const HITS = [
	{
		title: "Flakes",
		url: "https://wiki.nixos.org/wiki/Flakes",
		snippet: "Flakes are...",
	},
	{ title: "NixOS", url: "https://nixos.org/", snippet: "" },
];
const SEARCH_ERROR = {
	query: "x",
	results: ["Web search error: unavailable"],
	durationSeconds: expect.any(Number),
	searchCount: 1,
};
const LINKS = HITS.map(({ title, url }) => ({ title, url }));
const USAGE = {
	input_tokens: 1,
	output_tokens: 1,
	cache_read_input_tokens: 0,
	cache_creation_input_tokens: 0,
};

type Ran = { exitCode: number; stdout?: string; stderr?: string };
type Seen = {
	argvs: unknown[];
	asks: { model: string; system?: unknown; prompt: unknown }[];
};

function engine(
	on: Parameters<TestBody>[1],
	ran: Ran,
	summary: string | null = "Summary of the results.",
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
	on("session.model", () => ({ value: "claude-sonnet-5-5" }));
	on("model.complete", (_, e) => {
		seen.asks.push({ model: e.model, system: e.system, prompt: e.prompt });
		return {
			value:
				summary === null
					? {
							isAnswered: false as const,
							reason: "api-error" as const,
							status: 529,
							error: "overloaded" as const,
							usage: USAGE,
						}
					: { isAnswered: true, text: `\n${summary}\n`, usage: USAGE },
		};
	});
	return seen;
}

test(
	"WebSearch is recorded as the built-in tool records it",
	OPTIONS,
	async ($, on) => {
		const seen = engine(on, {
			exitCode: 0,
			stdout: JSON.stringify({ query: "q", hits: HITS }),
		});
		const answer = await $.tool.call({
			tool: "WebSearch",
			query: "-nix flakes",
			mode: "standard",
			allowed_domains: ["nixos.org"],
			blocked_domains: ["evil.example"],
		});
		expect(seen.argvs).toEqual([
			[
				COMMAND,
				"--json",
				"--limit",
				"10",
				"--allow",
				"nixos.org",
				"--block",
				"evil.example",
				"--",
				"-nix flakes",
			],
		]);
		expect(answer.deny).toBeUndefined();
		expect(answer.result).toEqual({
			query: "-nix flakes",
			results: [
				{
					tool_use_id: expect.stringMatching(/^srvtoolu_01[0-9A-Za-z]{22}$/),
					content: LINKS,
				},
				"Summary of the results.",
			],
			durationSeconds: expect.any(Number),
			searchCount: 1,
		});
	},
);

test(
	"the session's model summarizes with the built-in prompt",
	OPTIONS,
	async ($, on) => {
		const seen = engine(on, {
			exitCode: 0,
			stdout: JSON.stringify({ hits: HITS }),
		});
		await $.tool.call({
			tool: "WebSearch",
			query: "nix flakes",
			mode: "standard",
		});
		expect(seen.asks).toEqual([
			{
				model: "claude-sonnet-5-5",
				system:
					"You run a web search for another Claude model, which is waiting on the result and can search again. Search once, then reply with a brief summary of the results.",
				prompt: expect.stringMatching(
					/^Perform a web search for the query: nix flakes\n\n<search_results>\n1\. Flakes\nhttps:\/\/wiki\.nixos\.org\/wiki\/Flakes\nFlakes are\.\.\.\n\n2\. NixOS\nhttps:\/\/nixos\.org\/\n<\/search_results>$/,
				),
			},
		]);
	},
);

test("a summary that fails leaves the links", OPTIONS, async ($, on) => {
	engine(on, { exitCode: 0, stdout: JSON.stringify({ hits: HITS }) }, null);
	const answer = await $.tool.call({
		tool: "WebSearch",
		query: "x",
		mode: "standard",
	});
	expect(answer.result).toEqual(
		expect.objectContaining({
			results: [expect.objectContaining({ content: LINKS })],
		}),
	);
});

test(
	"no hits are an empty link list, with no model call",
	{ options: { searchCommand: COMMAND, maxResults: 3 } },
	async ($, on) => {
		const seen = engine(on, {
			exitCode: 0,
			stdout: JSON.stringify({ hits: [] }),
		});
		const answer = await $.tool.call({
			tool: "WebSearch",
			query: "x",
			mode: "standard",
		});
		expect(seen.argvs).toEqual([
			[COMMAND, "--json", "--limit", "3", "--", "x"],
		]);
		expect(seen.asks).toEqual([]);
		expect(answer.result).toEqual(
			expect.objectContaining({
				results: [expect.objectContaining({ content: [] })],
			}),
		);
	},
);

test(
	"a failure is the built-in search error, with no backend detail",
	OPTIONS,
	async ($, on) => {
		engine(on, {
			exitCode: 4,
			stderr:
				"kagi-search: Kagi rejected LibreWolf's session (signed out or expired); sign in to kagi.com in LibreWolf again\n",
		});
		const answer = await $.tool.call({
			tool: "WebSearch",
			query: "x",
			mode: "standard",
		});
		expect(answer.deny).toBeUndefined();
		expect(answer.result).toEqual(SEARCH_ERROR);
		expect(JSON.stringify(answer)).not.toMatch(/kagi|librewolf/i);
	},
);

test(
	"output that is not JSON hits is the built-in search error",
	OPTIONS,
	async ($, on) => {
		engine(on, { exitCode: 0, stdout: "1. Flakes\nhttps://wiki.nixos.org/\n" });
		const answer = await $.tool.call({
			tool: "WebSearch",
			query: "x",
			mode: "standard",
		});
		expect(answer.deny).toBeUndefined();
		expect(answer.result).toEqual(SEARCH_ERROR);
		expect(JSON.stringify(answer)).not.toMatch(/kagi|librewolf/i);
	},
);

test(
	"an unset searchCommand is the built-in search error without running anything",
	{ options: { searchCommand: "" } },
	async ($, on) => {
		const seen = engine(on, { exitCode: 0 });
		const answer = await $.tool.call({
			tool: "WebSearch",
			query: "x",
			mode: "standard",
		});
		expect(answer.deny).toBeUndefined();
		expect(answer.result).toEqual(SEARCH_ERROR);
		expect(JSON.stringify(answer)).not.toMatch(/kagi|librewolf/i);
		expect(seen.argvs).toEqual([]);
	},
);
