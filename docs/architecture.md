# EvalGate architecture

Overall design of the planned system. It is built incrementally: the first milestone is a
**local, Python-only evaluation system** (data structures → demo agent → trajectory scorer →
statistics). PostgreSQL and Redis are only needed from the backend phase onwards; GitHub
integration and the dashboard come after that.

## Components

```
 Customer CI (GitHub Actions) – bring your own runner
 ┌──────────────────────────────────────────────────────┐
 │ evalgate run                                         │
 │  ├─ git worktree @base ─ subprocess ─ agent ─┐       │
 │  ├─ @head ───────────── subprocess ─ agent ─┤ traces│
 │  └─ K repeats × N cases, tracer captures ───┘       │
 └───────────────┬──────────────────────────────────────┘
                 │ HTTPS, batched, idempotent (runId, caseId, variant, attempt)
                 ▼
 ┌─────────────── apps/server (one TS codebase) ────────┐     GitHub
 │ api: Express + Zod                                   │◀── webhooks (HMAC)
 │   webhook → record delivery → XADD gh.events → 2xx   │
 │   run/trace ingestion, verdict, dashboard REST       │
 │ worker: gh.events, gh.report consumers + sweeper     │──▶ Check Runs, PR comments
 └──────┬──────────────────────┬────────────────────────┘
        │ Prisma               │ XADD eval.score
        ▼                      ▼
   PostgreSQL 16 ◀──── services/scorer (Python)
   (source of truth)     trajectory → judge → statistics → verdict → XADD gh.report
        ▲
   Redis 7: Streams, rate limits, deterministic caches
        ▲
   apps/web (Next.js) ── server REST API only
```

Run lifecycle: `CREATED → UPLOADING → SCORING → COMPLETED | FAILED | TIMED_OUT`, every transition a
conditional update (`UPDATE … WHERE status = <expected>`).

## Module dependency map

```
packages/schemas (JSON Schema)
   ├─▶ generated zod      ──▶ apps/server ──▶ apps/web
   └─▶ generated pydantic ──▶ packages/evalgate-py (SDK + CLI)
                          └─▶ services/scorer
examples/refund-agent-demo ──▶ evalgate-py (tracer)

scorer:  trajectory/argmatch ─▶ trajectory/alignment ─▶ trajectory/metrics
         judge ─┐
         pipeline ◀─ trajectory ;  statistics ◀─ pipeline outputs
         worker ─▶ pipeline + statistics + db + redis
server:  lib/config ─▶ lib/{db,redis,logger,errors} ─▶ modules/* ─▶ api/, worker/
ml/judge (separate env) ──(.onnx + version)──▶ scorer/judge
```

## Local resource plan (8 GB)

| Workload | Approx. RAM | Where |
|---|---|---|
| Postgres + Redis | limits 384 MB + 192 MB | Docker |
| API + worker | ~250 MB | native |
| Scorer (+ ONNX judge later) | ~150–350 MB | native |
| Next.js dev | 0.5–1 GB | native, only while doing UI work |
| Ollama 3B (optional) | ~2.5 GB | native, never together with `next dev` |
| DeBERTa fine-tune / sweeps | – | Google Colab |

RAM numbers are estimates until measured (`make check-services` prints actual container memory).
