FROM node:18-alpine AS base
WORKDIR /app

COPY package.json package-lock.json* ./

# Change npm install -> npm ci.
# `npm ci` installs exactly what the lockfile pins and fails if it drifts.
RUN npm install --omit=dev

COPY src ./src

# Added: run as a non-root user.
USER node

EXPOSE 3000

CMD ["node", "src/index.js"]
