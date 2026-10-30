# Cloudflare Containers storage

A container has an ephemeral local disk; anything that must survive a restart goes to Durable Object storage, R2, or Workers KV.

| Storage type           | Persistence | Capacity       | Use case            |
| ---------------------- | ----------- | -------------- | ------------------- |
| Container disk         | Ephemeral   | 2-20 GB        | Temp files, cache   |
| Durable Object storage | Persistent  | Up to 10 GB    | App state, metadata |
| [R2 FUSE mount][r2]    | Persistent  | Unlimited      | Files, large data   |
| Workers KV             | Persistent  | Per-key limits | Config, sessions    |

## Container disk

- **Ephemeral**: cleared on every restart and sleep; a restarted container sees only the image's files.
- **Size**: set by the [instance type](./README.md#instance-types), 2 to 20 GB.
- **Performance**: fast, local SSD-like.
- **Access**: standard filesystem operations.

```text
# Good uses for ephemeral disk
/tmp/                  # Temporary files
/var/cache/            # Runtime caches
/app/uploads/temp/     # Uploads processed before moving to R2

# Bad uses (data will be lost)
/data/database.sqlite  # Database files
/app/user_uploads/     # Permanent user files
/var/log/persistent/   # Logs that must be kept
```

## Durable Object storage

The Container class extends `DurableObject`, so it has full access to Durable Object storage.

| Metric                     | Limit                        |
| -------------------------- | ---------------------------- |
| Storage per Durable Object | Up to 10 GB (SQLite backend) |
| Key size                   | 2 KB                         |
| Value size                 | 128 KB (key-value API)       |

### SQLite

SQLite is the recommended backend.
Tables are created on start, for example from `onStart()`:

```typescript
export class MyContainer extends Container {
  async onStart() {
    await this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        data TEXT,
        created_at INTEGER
      )
    `);
  }

  async saveSession(id: string, userId: string, data: object) {
    await this.ctx.storage.sql.exec(
      `INSERT OR REPLACE INTO sessions (id, user_id, data, created_at)
       VALUES (?, ?, ?, ?)`,
      id,
      userId,
      JSON.stringify(data),
      Date.now(),
    );
  }

  async getSession(id: string) {
    const result = await this.ctx.storage.sql.exec(
      `SELECT * FROM sessions WHERE id = ?`,
      id,
    );
    return result.rows[0];
  }
}
```

### Key-value

```typescript
export class MyContainer extends Container {
  async saveConfig(config: object) {
    await this.ctx.storage.put("config", config);
  }

  async getConfig() {
    return await this.ctx.storage.get("config");
  }

  async saveMultiple(data: Map<string, any>) {
    await this.ctx.storage.put(Object.fromEntries(data));
  }

  async getMultiple(keys: string[]) {
    return await this.ctx.storage.get(keys);
  }

  async clearSession(id: string) {
    await this.ctx.storage.delete(`session:${id}`);
  }
}
```

### Restoring state across restarts

`onStart` and `onStop` can move state between Durable Object storage and the container:

```typescript
class MyContainer extends Container {
  async onStart() {
    const state = await this.ctx.storage.get("appState");
    if (state) {
      await this.loadStateToContainer(state);
    }
  }

  async onStop() {
    const state = await this.extractStateFromContainer();
    await this.ctx.storage.put("appState", state);
  }
}
```

Critical data never goes to the ephemeral disk:

```typescript
// Lost on the next restart
fs.writeFileSync("/data/important.json", data);

// Persistent
await this.ctx.storage.put("important", data);
```

[r2]: ./r2-mount.md
