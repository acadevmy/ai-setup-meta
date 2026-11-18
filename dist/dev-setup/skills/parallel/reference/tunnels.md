# Tunnels

Two directions, two different tools.

## Outbound — the local app reaches a remote service

Port-forwards (`kubectl port-forward`, `ssh -L`) to an API or a database in a
remote environment. One fixed port per environment, shared by every worktree:
each worktree's `.env` points at it. They go in the script's `CONFIG.outbound`,
and `tunnels` (or `up`) reopens each one a few seconds after it drops — an idle
timeout or an expired token is the normal case, not an error.

They need the developer's cloud credentials (`~/.kube`, `~/.aws`) and network
the sandbox does not allow: the developer runs them.

## Inbound — the outside reaches one worktree

`expose [name] [--service s]` opens a cloudflared quick tunnel to one
worktree's service and prints a public `https://…trycloudflare.com` URL. Good
for opening the app on a phone, or for a webhook whose URL can be set on the
fly. Its URL changes on every start, so it is wrong for anything registered
in advance — an OAuth callback, a webhook configured once in a provider's
dashboard.

For Stripe, `stripe listen --forward-to localhost:<port>/<path>` per worktree
is the better tool: no public URL, and the signing secret it prints goes in
that worktree's `.env`.

Anything exposed this way is reachable by anyone with the URL: never on a
worktree pointed at production data.
