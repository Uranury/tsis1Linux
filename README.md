# tsis1Linux

A small Go REST API for managing todo tasks, with JWT-based auth and refresh-token rotation. Built as the application layer for a Linux/DevOps coursework project (3-tier deploy: Nginx → this API → Postgres).

## Stack

- Go 1.26, stdlib `net/http` (Go 1.22+ method+pattern routing, no router dependency)
- Postgres via `jackc/pgx/v5`
- `golang-migrate` for schema migrations, embedded into the binary via `embed.FS`
- `golang-jwt/jwt/v5` for access tokens, bcrypt for passwords

## Running it

Requires a reachable Postgres instance. Copy `.env.example` to `.env` (or export the same variables in your shell/systemd unit — the app does not load `.env` files itself):

```bash
cp .env.example .env
export $(cat .env | xargs)   # or your preferred way of loading it
go run ./cmd/app
```

Required: `DATABASE_URL`, `JWT_SECRET`. Everything else has a default — see `.env.example`.

Schema migrations run automatically on startup; nothing to apply by hand.

## API

All request/response bodies are JSON.

| Method | Path              | Auth | Description                          |
|--------|-------------------|------|---------------------------------------|
| POST   | `/auth/register`  | –    | Create an account                     |
| POST   | `/auth/login`     | –    | Get an access + refresh token pair    |
| POST   | `/auth/refresh`   | –    | Rotate a refresh token for a new pair |
| POST   | `/auth/logout`    | –    | Revoke one refresh token              |
| POST   | `/auth/logout-all`| Bearer | Revoke every refresh token for the user ("log out everywhere") |
| POST   | `/tasks`          | Bearer | Create a task                       |
| GET    | `/tasks`          | Bearer | List your tasks                     |
| GET    | `/tasks/{id}`     | Bearer | Get one task                        |
| PUT    | `/tasks/{id}`     | Bearer | Update a task                       |
| DELETE | `/tasks/{id}`     | Bearer | Delete a task                       |
| GET    | `/healthz`        | –    | Liveness check                        |

"Bearer" routes require `Authorization: Bearer <access_token>`. Access tokens are short-lived (`ACCESS_TOKEN_TTL`, default 15m); use `/auth/refresh` with the refresh token to get a new pair.

## Development

```bash
go build ./...
go vet ./...
gofmt -l .              # should print nothing
golangci-lint run ./...
go test ./...
```

CI (`.github/workflows/ci.yml`) runs all of the above on every push and PR to `master`.

## Project layout

See `CLAUDE.md` for the package-by-package breakdown and the conventions the codebase follows (repo/service/handler layering, transaction usage, auth design, etc.).
