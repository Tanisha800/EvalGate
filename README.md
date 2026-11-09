# EvalGate

**Regression testing for AI agents.** When you change an agent's prompt, tools or model, EvalGate
runs your golden test cases against the old (BASE) and new (HEAD) versions, scores *how* the agent
solved each case – not just its final answer – and decides **PASS / WARN / FAIL** using statistics.

> Status: early development. Environment set up; the core data structures are next.

## Why
A prompt change can make a refund agent skip its policy check or refund the wrong amount while the
final answer still sounds convincing. Tests that only look at the final answer miss this.

## Features (planned)
- **Trajectory evaluation** – were the right tools called, in the right order, with the right arguments?
  Were there unnecessary or forbidden calls?
- **Statistical regression detection** – every case runs several times; a paired bootstrap decides
  whether HEAD is really worse than BASE or the difference is just noise.
- **Answer evaluation** – a baseline scorer first, a small trained ML judge later.
- **GitHub integration** – results appear as a Check Run on the pull request.
- **Bring your own runner** – your CI runs your agent; EvalGate only scores the uploaded traces.

## Tech stack
| Part | Technology |
|---|---|
| Evaluation engine, CLI, demo agent | Python 3.11, LangGraph, NumPy/SciPy |
| Backend API | Node.js 22, Express, TypeScript, Zod |
| Database | PostgreSQL 16 + Prisma |
| Background jobs | Redis 7 (added in the backend phase) |
| Dashboard | Next.js + Tailwind CSS |
| Tests | Pytest, Vitest |

Architecture: [docs/architecture.md](docs/architecture.md)

## Setup
Prerequisites: Node 22 ([nvm](https://github.com/nvm-sh/nvm)), pnpm 11.22.0, [uv](https://docs.astral.sh/uv/)
(installs Python 3.11), Docker Desktop (only needed from the backend phase; ~2 GB memory is enough).

```bash
nvm use          # switch to Node 22 (reads .nvmrc)
make check       # verify Node, pnpm, uv and Python versions
```

Local database and Redis (needed from the backend phase onwards):
```bash
make env              # create .env from .env.example
make up               # start Postgres + Redis
make check-services   # verify they work
make down             # stop them (data is kept)
```
To delete all local database/Redis data: `docker compose down -v`.

Run `make` to see all commands.

## License
Not yet chosen.
