## Quickstart

the minimum to start meilisearch is

```programlisting
{ services.meilisearch.enable = true; }
```

this will start the http server included with meilisearch on port 7700.

test with `curl -X GET 'http://localhost:7700/health'`
