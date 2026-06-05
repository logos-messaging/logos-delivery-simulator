FROM node:22-slim

WORKDIR /app

COPY package.json package-lock.json* ./

RUN npm ci

COPY . .

ENTRYPOINT ["node", "index.ts"]

