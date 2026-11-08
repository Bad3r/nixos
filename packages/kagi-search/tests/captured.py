# Copyright (c) 2026 Bad3r
"""Calls captured from the real web.run service, reproduced by the parity tests."""

# Output and results of the captured service calls, by record number.
CAPTURED: dict[int, tuple[str, list[dict[str, object]]]] = {
    0: (
        (
            "Internal Error ()\n\ue200cite\ue202turn0view0\ue201 [wordlim: 200] Source: "
            'open({"ref_id":"https://does-not-exist-zq7x.invalid/","lineno":null}); \nURL '
            "https://does-not-exist-zq7x.invalid/ is not accessible via this tool."
        ),
        [
            {
                "type": "text_result",
                "ref_id": "turn0view0",
                "title": "Internal Error",
            },
        ],
    ),
    3: (
        (
            "ClientResponseError\n500, message='Internal Server Error', "
            "url='http://search.openai.svc.cluster.local.:8000/internal/tool_call/process_statele"
            "ss'"
        ),
        [],
    ),
    4: (
        (
            "Example Domain (https://example.com/)\n\ue200cite\ue202turn4view0\ue201 [wordlim: "
            "200] Crawled: today; Content type: text/html; Source: "
            'open({"ref_id":"https://example.com/","lineno":null}); Total lines: 1\nL0: This '
            "domain is for use in documentation examples without needing permission. This is not "
            "a service; avoid relying on it for testing and monitoring purposes.\n"
            "--------------------------------------------------------------------------------\n"
            "Internal Error ()\n\ue200cite\ue202turn4view1\ue201 [wordlim: 200] Source: "
            'open({"ref_id":"https://does-not-exist-zq7x.invalid/","lineno":null}); \nURL '
            "https://does-not-exist-zq7x.invalid/ is not accessible via this "
            "tool.-------------------------------------------------------------------------------"
            "-\nInternal Error ()\n\ue200cite\ue202turn4view2\ue201 [wordlim: 200] Source: "
            'open({"ref_id":"https://httpbin.org/status/404","lineno":null}); \nURL '
            "https://httpbin.org/status/404 is not accessible via this tool."
        ),
        [
            {
                "type": "text_result",
                "domain": "example.com",
                "ref_id": "turn4view0",
                "snippet": "Total lines: 1",
                "title": "Example Domain",
                "url": "https://example.com/",
            },
            {
                "type": "text_result",
                "ref_id": "turn4view1",
                "title": "Internal Error",
            },
            {
                "type": "text_result",
                "ref_id": "turn4view2",
                "title": "Internal Error",
            },
        ],
    ),
    5: (
        (
            "Example Domain (https://example.com/)\n\ue200cite\ue202turn0view0\ue201 [wordlim: "
            "200] Crawled: today; Content type: text/html; Source: "
            'open({"ref_id":"https://example.com/","lineno":null}); Total lines: 1\nL0: This '
            "domain is for use in documentation examples without needing permission. This is not "
            "a service; avoid relying on it for testing and monitoring purposes.\n"
        ),
        [
            {
                "type": "text_result",
                "domain": "example.com",
                "ref_id": "turn0view0",
                "snippet": "Total lines: 1",
                "title": "Example Domain",
                "url": "https://example.com/",
            },
        ],
    ),
    6: (
        (
            "Internal Error ()\n\ue200cite\ue202turn1view0\ue201 [wordlim: 200] Unable to "
            "resolve click call due to invalid arguments\nL0: Unable to resolve click call due "
            "to invalid arguments\n"
        ),
        [
            {
                "type": "text_result",
                "ref_id": "turn1view0",
                "snippet": "Unable to resolve click call due to invalid arguments",
                "title": "Internal Error",
            },
        ],
    ),
    7: (
        (
            "ClientResponseError\n500, message='Internal Server Error', "
            "url='http://search.openai.svc.cluster.local.:8000/internal/tool_call/process_statele"
            "ss'"
        ),
        [],
    ),
    8: (
        (
            "ClientResponseError\n500, message='Internal Server Error', "
            "url='http://search.openai.svc.cluster.local.:8000/internal/tool_call/process_statele"
            "ss'"
        ),
        [],
    ),
    9: (
        (
            "Example Domain (https://example.com/)\n\ue200cite\ue202turn4view0\ue201 [wordlim: "
            "200] Crawled: today; Content type: text/html; Source: "
            'find({"ref_id":"turn0view0","pattern":"zqxjkvw"}); Total lines: 1\nNo matching text '
            'found for "zqxjkvw"'
        ),
        [
            {
                "type": "text_result",
                "domain": "example.com",
                "ref_id": "turn4view0",
                "snippet": "Total lines: 1",
                "title": "Example Domain",
                "url": "https://example.com/",
            },
        ],
    ),
    10: (
        (
            "Example Domain (https://example.com/)\n\ue200cite\ue202turn5view0\ue201 [wordlim: "
            "200] Crawled: today; Content type: text/html; Source: "
            'find({"ref_id":"turn0view0","pattern":"documentation"}); Total lines: 1\nL0: This '
            "domain is for use in documentation examples without needing permission. This is not "
            "a service; avoid relying on it for testing and monitoring purposes.\n"
        ),
        [
            {
                "type": "text_result",
                "domain": "example.com",
                "ref_id": "turn5view0",
                "snippet": "Total lines: 1",
                "title": "Example Domain",
                "url": "https://example.com/",
            },
        ],
    ),
    11: (
        (
            "Example Domain (https://example.com/)\n\ue200cite\ue202turn6view0\ue201 [wordlim: "
            "200] Crawled: today; Content type: text/html; Source: "
            'open({"ref_id":"turn0view0","lineno":500}); Total lines: 1\nL0: This domain is for '
            "use in documentation examples without needing permission. This is not a service; "
            "avoid relying on it for testing and monitoring purposes.\n"
        ),
        [
            {
                "type": "text_result",
                "domain": "example.com",
                "ref_id": "turn6view0",
                "snippet": "Total lines: 1",
                "title": "Example Domain",
                "url": "https://example.com/",
            },
        ],
    ),
    12: (
        (
            "Example Domain (https://example.com/)\n\ue200cite\ue202turn7view0\ue201 [wordlim: "
            "200] Crawled: today; Content type: text/html; Source: "
            'find({"ref_id":"turn0view0","pattern":"documentation"}); Total lines: 1\nL0: This '
            "domain is for use in documentation examples without needing permission. This is not "
            "a service; avoid relying on it for testing and monitoring purposes.\n"
            "--------------------------------------------------------------------------------\n"
            "Example Domain (https://example.com/)\n\ue200cite\ue202turn7view1\ue201 [wordlim: "
            "200] Crawled: today; Content type: text/html; Source: "
            'find({"ref_id":"turn0view0","pattern":"zqxjkvw"}); Total lines: 1\nNo matching text '
            'found for "zqxjkvw"'
        ),
        [
            {
                "type": "text_result",
                "domain": "example.com",
                "ref_id": "turn7view0",
                "snippet": "Total lines: 1",
                "title": "Example Domain",
                "url": "https://example.com/",
            },
            {
                "type": "text_result",
                "domain": "example.com",
                "ref_id": "turn7view1",
                "snippet": "Total lines: 1",
                "title": "Example Domain",
                "url": "https://example.com/",
            },
        ],
    ),
    13: (
        "Empty search results\nNo results were found for the provided queries",
        [],
    ),
    16: (
        (
            "ClientResponseError\n500, message='Internal Server Error', "
            "url='http://search.openai.svc.cluster.local.:8000/internal/tool_call/process_statele"
            "ss'"
        ),
        [],
    ),
    19: (
        " (https://arxiv.org/pdf/1706.03762)\n\ue200cite\ue202turn1view0\ue201 ",
        [],
    ),
    20: (
        (
            "Internal Error ()\n\ue200cite\ue202turn2view0\ue201 [wordlim: 200] Source: "
            'screenshot({"ref_id":"turn0view0","pageno":999,"height":null,"offset":null}); \n'
            "Failed to fetch https://arxiv.org/pdf/1706.03762: Internal Error"
        ),
        [
            {
                "type": "text_result",
                "ref_id": "turn2view0",
                "title": "Internal Error",
            },
        ],
    ),
    21: (
        (
            " "
            "(https://upload.wikimedia.org/wikipedia/commons/4/47/PNG_transparency_demonstration_"
            "1.png)\n\ue200cite\ue202turn3view0\ue201 This page has no readable lines."
        ),
        [],
    ),
    23: (
        (
            "Internal Error ()\n\ue200cite\ue202turn5view0\ue201 [wordlim: 200] Unable to "
            "resolve screenshot call because content type is not application/pdf and web "
            "screenshot is not enabled\nL0: Unable to resolve screenshot call because content "
            "type is not application/pdf and web screenshot is not enabled\n"
        ),
        [
            {
                "type": "text_result",
                "ref_id": "turn5view0",
                "snippet": (
                    "Unable to resolve screenshot call because content type is not "
                    "application/pdf and web screenshot is not enabled"
                ),
                "title": "Internal Error",
            },
        ],
    ),
    27: (
        (
            "Error parsing function call: Invalid function_name='run' call: kwargs={'sports': "
            "[{'fn': 'schedule', 'league': 'nba', 'num_games': 3}]}. Expected: type run = (_: {\n"
            "// Open the page indicated by `ref_id` and position viewport at the line number "
            '`lineno`.\n// In addition to reference ids (like "turn0search1"), you can also use '
            "the fully qualified URL.\n// If `lineno` is not provided, the viewport will be "
            "positioned at the beginning of the document or centered on\n// the most relevant "
            "passage, if available.\n// You can use this to scroll to a new location of "
            "previously opened pages.\nopen?: {\n  ref_id: string;\n  lineno: number | null;\n"
            "}[] | null,\n// Open the link `id` from the page indicated by `ref_id`.\n// Valid "
            "link ids are displayed with the formatting: `【{id}†.*】`.\nclick?: {\n  ref_id: "
            "string;\n  id: number;\n}[] | null,\n// Find the text `pattern` in the page "
            "indicated by `ref_id`.\nfind?: {\n  ref_id: string;\n  pattern: string;\n}[] | "
            "null,\n// Take a screenshot of the page `pageno` indicated by `ref_id`. Currently "
            "only works on pdfs.\n// `pageno` is 0-indexed and can be at most the number of pdf "
            "pages -1.\nscreenshot?: {\n  ref_id: string;\n  pageno: number;\n}[] | null,\n// "
            "query image search engine for a given list of queries\nimage_query?: {\n  q: "
            "string;\n  recency: number | null;\n  domains: string[] | null;\n}[] | null,\n// "
            "look up sports schedules and standings for games in a given league\nsports?: {\n  "
            'tool: "sports";\n  fn: "schedule" | "standings";\n  league: "nba" | "wnba" | "nfl" '
            '| "nhl" | "mlb" | "epl" | "ncaamb" | "ncaawb" | "ipl";\n  team: string | null;\n  '
            "opponent: string | null;\n  date_from: string | null;\n  date_to: string | null;\n  "
            "num_games: number | null;\n  locale: string | null;\n}[] | null,\n// look up prices "
            'for a given list of stock symbols\nfinance?: {\n  ticker: string;\n  type: "equity" '
            '| "fund" | "crypto" | "index";\n  market: string | null;\n}[] | null,\n// look up '
            "weather for a given list of locations\nweather?: {\n  location: string;\n  start: "
            "string | null;\n  duration: number | null;\n}[] | null,\n// get time for the given "
            "list of UTC offsets\ntime?: {\n  utc_offset: string;\n}[] | null,\n// the length of "
            'the response to be returned\nresponse_length?: "short" | "medium" | "long", // '
            "default: medium\n// query internet search engine for a given list of queries\n"
            "search_query?: {\n  q: string;\n  recency: number | null;\n  domains: string[] | "
            "null;\n}[] | null,\n}) => any;"
        ),
        [],
    ),
    28: (
        ("\ue200cite\ue202turn4time0\ue201 The time in UTC+03:00 is Nov 8, 2026, 1:39:43\u202fAM"),
        [],
    ),
    29: (
        "Found no tool response. This likely means the arguments you provided were not valid.",
        [],
    ),
    34: (
        (
            "Example Domain (https://example.com/)\n\ue200cite\ue202turn3view0\ue201 [wordlim: "
            "200] Crawled: today; Content type: text/html; Source: "
            'open({"ref_id":"https://example.com/","lineno":null}); Total lines: 1\nL0: This '
            "domain is for use in documentation examples without needing permission. This is not "
            "a service; avoid relying on it for testing and monitoring purposes.\n"
        ),
        [
            {
                "type": "text_result",
                "domain": "example.com",
                "ref_id": "turn3view0",
                "snippet": "Total lines: 1",
                "title": "Example Domain",
                "url": "https://example.com/",
            },
        ],
    ),
    35: (
        (
            "\ue200cite\ue202turn0time0\ue201 The time in UTC+03:00 is Nov 8, 2026, "
            "1:41:42\u202fAM---------------------------------------------------------------------"
            "-----------\n\ue200cite\ue202turn0time1\ue201 The time in UTC-05:00 is Nov 7, 2026, "
            "5:41:42\u202fPM"
        ),
        [],
    ),
    36: (
        (
            "Empty search results\nNo results were found for the provided "
            "queries-----------------------------------------------------------------------------"
            "---\nExample Domain (https://example.com/)\n\ue200cite\ue202turn1view0\ue201 "
            "[wordlim: 200] Crawled: today; Content type: text/html; Source: "
            'open({"ref_id":"https://example.com/","lineno":null}); Total lines: 1\nL0: This '
            "domain is for use in documentation examples without needing permission. This is not "
            "a service; avoid relying on it for testing and monitoring purposes.\n"
            "--------------------------------------------------------------------------------\n"
            "\ue200cite\ue202turn1time0\ue201 The time in UTC+00:00 is Nov 7, 2026, "
            "10:41:49\u202fPM"
        ),
        [
            {
                "type": "text_result",
                "domain": "example.com",
                "ref_id": "turn1view0",
                "snippet": "Total lines: 1",
                "title": "Example Domain",
                "url": "https://example.com/",
            },
        ],
    ),
    37: (
        "Found no tool response. This likely means the arguments you provided were not valid.",
        [],
    ),
}
