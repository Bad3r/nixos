# Songbird runbook: paperless

- [songbird-local-ai.md](songbird-local-ai.md)
- [songbird-runbook-local-ai.md](songbird-runbook-local-ai.md)

## Set up paperless

Precondition: songbird runs a generation from [paperless.nix](../../../modules/apps/paperless.nix), and `/data` is mounted.

1. Create the first login:

   ```sh
   sudo paperless-manage createsuperuser
   ```

2. Open `http://<songbird-address>:28981` from the LAN or the Mesh and sign in.

3. Under Workflows, add a workflow with the Document Added trigger and an Apply AI Suggestions action.
   Select tags, correspondent, document type, and storage path, and leave both creating missing items and overwriting existing values off.

Verification: a PDF copied into `/data/paperless/consume` leaves the inbox, shows up in the document list, and gains suggested values in the fields it had empty.

## Check the AI services

Precondition: [Set up paperless](#set-up-paperless) has run.

1. Show the paperless units and the embeddings server:

   ```sh
   systemctl status paperless-web paperless-task-queue llama-cpp-embed
   ```

2. Embed a word with the paperless key, and send a request without it:

   ```sh
   sudo sed 's/^/Authorization: Bearer /' /run/secrets/llama-cpp/paperless-api-key | curl -s -H @- -H 'Content-Type: application/json' -d '{"input": "ready"}' http://127.0.0.1:10101/v1/embeddings | jq '.data[0].embedding | length'
   curl -s -o /dev/null -w '%{http_code}\n' -H 'Content-Type: application/json' -d '{"input": "ready"}' http://127.0.0.1:10101/v1/embeddings
   ```

3. Check that the router accepts the paperless key, which lists models without loading one:

   ```sh
   sudo sed 's/^/Authorization: Bearer /' /run/secrets/llama-cpp/paperless-api-key | curl -s -o /dev/null -w '%{http_code}\n' -H @- http://127.0.0.1:10100/v1/models
   ```

Verification: every unit is `active (running)`, step 2 prints the vector length and then `401`, and step 3 prints `200`.

## Write an export after a late switch

Precondition: a switch that started or changed `paperless-exporter.timer` ran after 23:00, so the timer, which does not catch up on a missed run, waits until the next night.

1. Run the export now, so the next `r2-restic` backup carries it:

   ```sh
   sudo systemctl start paperless-exporter
   ```

Verification: `systemctl show paperless-exporter -p Result` prints `Result=success`, and `/data/paperless/export/manifest.json` carries the current time.

## Rebuild the AI index after an embedding model change

Precondition: songbird runs a generation whose `programs.llama-cpp.extended.embeddings.model` differs from the one the index was built with.

1. Re-embed every document:

   ```sh
   sudo paperless-manage document_llmindex rebuild
   ```

Verification: the command exits 0, and the document chat answers a question about a stored document.

## Restore from the export

Precondition: an empty paperless instance on a fresh generation, and the export directory restored from `r2-restic`.

1. Stop the export timer and the units that write to the database, since a nightly export during the import deletes files from the export directory and restarts the services:

   ```sh
   sudo systemctl stop paperless-exporter.timer paperless-scheduler paperless-web paperless-task-queue paperless-consumer
   ```

2. Hand the restored files to the paperless user, since the restore leaves them owned by the owner with mode 0600:

   ```sh
   sudo chown -R paperless:paperless /data/paperless/export
   ```

3. Import the export:

   ```sh
   sudo paperless-manage document_importer /data/paperless/export
   ```

4. Start the units and the export timer again, then rebuild the AI index as above:

   ```sh
   sudo systemctl start paperless-exporter.timer paperless-scheduler paperless-web paperless-task-queue paperless-consumer
   ```

Verification: the document list matches the exported `manifest.json` count.
