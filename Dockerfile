FROM node:18-alpine AS base
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install --omit=dev

COPY src ./src

# Deliberately left as a discussion point in the take-home:
# this container currently runs as root. Candidates are not
# required to fix this, but it's fair game to ask about it.
EXPOSE 3000
CMD ["node", "src/index.js"]
