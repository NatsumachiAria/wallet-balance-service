# wallet-balance-service (sample app)

A minimal Express service with three endpoints, provided as the app you'll
deploy for the DevOps take-home exercise. You are not being evaluated on
this application code — treat it as a fixed input.

## Endpoints

- `GET /health` — liveness check, no dependencies. Always returns 200 if the process is up.
- `GET /ready` — readiness check, verifies DB connectivity. Returns 503 if the DB is unreachable.
- `GET /balance/:userId` — returns a mock wallet balance from Postgres. Try `user-001`, `user-002`, `user-003`.

## Running locally

```bash
npm install
cp .env.example .env   # point DATABASE_URL at a local/dev Postgres instance
psql "$DATABASE_URL" -f db/schema.sql
npm start
```

## Running tests

```bash
npm test
```

## Building the container

```bash
docker build -t wallet-balance-service .
docker run -p 3000:3000 --env-file .env wallet-balance-service
```

You're free to modify this app minimally if your infrastructure approach
requires it (e.g. adding a `/metrics` endpoint), but the core exercise is
about what you build *around* it, not the app itself.
