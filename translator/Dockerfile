# The call translator, as LiveKit Cloud builds and runs it (`lk agent create` / `lk agent deploy`, see README.md).
FROM node:24-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY src ./src
# Node runs the TypeScript directly.
CMD ["node", "src/agent.ts", "start"]
