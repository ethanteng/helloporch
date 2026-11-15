# The call translator, as LiveKit Cloud builds and runs it (`lk agent create` / `lk agent deploy`, see README.md).
FROM node:24-slim
# LiveKit's native client checks TLS against the system's certificates, which the slim image leaves out.
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY src ./src
# Node runs the TypeScript directly.
CMD ["node", "src/agent.ts", "start"]
