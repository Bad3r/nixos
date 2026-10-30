# Cloudflare Containers example: WebSocket chat

Real-time chat over WebSockets, with one container per chat room.

## Dockerfile

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 8080
CMD ["node", "chat-server.js"]
```

## Chat server (chat-server.js)

```javascript
const WebSocket = require("ws");
const http = require("http");

const server = http.createServer();
const wss = new WebSocket.Server({ server });

const rooms = new Map();

wss.on("connection", (ws, req) => {
  const url = new URL(req.url, "http://localhost");
  const room = url.searchParams.get("room") || "default";
  const username = url.searchParams.get("username") || "anonymous";

  // Join room
  if (!rooms.has(room)) {
    rooms.set(room, new Set());
  }
  rooms.get(room).add(ws);

  console.log(`${username} joined ${room}`);

  // Broadcast join
  broadcast(room, { type: "join", username, room });

  ws.on("message", (data) => {
    const message = JSON.parse(data);
    broadcast(room, {
      type: "message",
      username,
      text: message.text,
      timestamp: Date.now(),
    });
  });

  ws.on("close", () => {
    rooms.get(room).delete(ws);
    broadcast(room, { type: "leave", username, room });
  });
});

function broadcast(room, message) {
  const clients = rooms.get(room);
  if (clients) {
    const data = JSON.stringify(message);
    clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(data);
      }
    });
  }
}

server.listen(8080);
console.log("Chat server running on port 8080");
```

## Worker (src/index.ts)

The `CHAT_SERVER` binding needs the `ChatServer` container, Durable Object binding, and migration entries in [`wrangler.jsonc`](../configuration.md#wrangler-configuration).

```typescript
import { Container, getContainer } from "@cloudflare/containers";

export class ChatServer extends Container {
  defaultPort = 8080;
  sleepAfter = "30m"; // Keep alive for active chats
}

export default {
  async fetch(request: Request, env: Env) {
    const url = new URL(request.url);
    const room = url.searchParams.get("room") || "default";

    // Validate WebSocket upgrade
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("WebSocket required", { status: 426 });
    }

    // Route to room-specific container
    const chatServer = getContainer(env.CHAT_SERVER, `room-${room}`);
    return chatServer.fetch(request);
  },
};
```
