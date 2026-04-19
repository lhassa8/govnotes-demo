# Govnotes app

Minimal Express service that backs the Govnotes product. This codebase
is intentionally thin — most of the platform's business logic lives in
the commercial codebase; the FedRAMP edition only carries what it needs.

## Layout

```
src/
├── server.js          Entry point. Wires middleware and routes.
├── config.js          Env-var parsing.
├── auth/              JWT middleware, login/logout.
├── notes/             Notes CRUD routes.
├── users/             /users/me route.
└── lib/               db, logger, errors.
tests/                 Vitest tests.
```

## Local development

You need Node 20 and a running Postgres 15. Then:

```
cp .env.example .env
npm install
npm run db:migrate
npm run dev
```

The server binds to `$PORT` (default 3000). A health check is at
`/health`.

## Tests

```
npm test
```

Coverage is thin by design; the FedRAMP edition piggybacks on the
commercial test suite for most product behavior.

## Things that aren't implemented here

- Real S3 uploads. `POST /notes/:id/attachments` returns a stub
  presigned-URL response.
- Real email for password reset.
- Background jobs — the commercial side runs those.
