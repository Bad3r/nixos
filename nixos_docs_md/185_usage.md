## Usage

you first need to add documents to an index before you can search for documents.

### Add a documents to the `movies` index

`curl -X POST 'http://127.0.0.1:7700/indexes/movies/documents' --data '[{"id": "123", "title": "Superman"}, {"id": 234, "title": "Batman"}]'`

### Search documents in the `movies` index

`curl 'http://127.0.0.1:7700/indexes/movies/search' --data '{ "q": "botman" }'` (note the typo is intentional and there to demonstrate the typo tolerant capabilities)
