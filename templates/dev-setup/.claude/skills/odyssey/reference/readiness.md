# Readiness

What stops two copies of the project from running together on one machine, and
the smallest change for each. Nothing is applied before the developer's yes.

## Where to look

- `package.json` (root and sub-projects), `Makefile`, `justfile`,
  `Taskfile.yml`, `scripts/`
- `docker-compose*.yml`, `compose*.yml`, `Dockerfile*`
- `.env.example` — variable names only. Do not read a real `.env` for this:
  the names are enough, and values never go in the report
- framework configuration: `next.config.*`, `nuxt.config.*`, `vite.config.*`,
  `nest-cli.json`, `angular.json`, `astro.config.*`, Strapi's `config/server.*`
- `README`, `CONTRIBUTING`, `AGENTS.md`: local setup is often described there
- scripts for worktrees or tunnels: when they exist, the project is ready and
  the analysis stops here

## The blockers

| Blocker | How it shows | Typical fix |
|---|---|---|
| Fixed port | `--port 3000`, `listen(3000)` | read it from `PORT`, with today's value as the default |
| Fixed container or volume names | `container_name:`, explicit volume `name:` | drop `container_name`; `compose: true` in `CONFIG` gives each worktree its own `COMPOSE_PROJECT_NAME` |
| Fixed published ports | `"5432:5432"` | `"${DB_PORT:-5432}:5432"`, with `DB_PORT` in `env.vars` |
| Shared database | one `DATABASE_URL` for all | the developer decides: one per worktree (its own container) or shared. Shared is fine read-only; different migrations on different branches break it |
| Cookies | session or auth on `localhost` | cookies ignore the port, so two instances on `localhost` overwrite each other's session. Use `<name>.localhost` subdomains (they resolve to 127.0.0.1 with no hosts file) and a per-worktree `APP_URL` |
| Absolute URLs | `APP_URL`, `NEXTAUTH_URL`, `PUBLIC_URL`, CORS origins | per worktree, in `env.vars` |
| OAuth callbacks | redirect URIs registered with the provider | they do not multiply: one worktree at a time on the registered port, or register several. Quick tunnels do not help — their URL is random |
| Webhooks | payments, CMS | Stripe: `stripe listen --forward-to localhost:<port>/…` per worktree. Others: `expose`, knowing the URL changes on every start |
| Secrets | gitignored `.env`, a vault | `env.source` and `env.copy`; a vault's local identity file has to be copied too |
| Remote services | the local app talks to staging or production through a port-forward | `outbound` in `CONFIG`, one fixed port per environment |
| Production within reach | production env files, production kube contexts | `productionBranch` in `CONFIG`, and an explicit warning in the report |
| Heavy setup | install, monorepo library builds, codegen | `setup` in `CONFIG`, in order; state the cost in time and disk |

## The report

Short, in this shape:

1. **Verdict**: ready, ready with changes, or not parallelisable without the
   developer's decisions.
2. **Blockers found**: for each, file and line, why it blocks, the fix.
3. **Decisions for the developer**: shared or per-worktree database, which
   services to start, which tunnels.
4. **Proposed configuration**: the script's `CONFIG` block, filled in.
