# Container execution (DooD) — building and running the app's own stack

Added 2026-07-04. Companion to `docs/MOUNTS.md` (that doc covers what's
mounted into the Hermes container; this one covers how the team reaches a
Docker engine from inside it, since a container has none of its own).

## Why this exists

Project instructions routinely have the team validate against a built
container to mirror prod — but the team's own container has no Docker
daemon, and can't reach the host's unless we deliberately give it one. See
the source design doc for the full options survey (privileged DinD, Sysbox,
K8s creds) and why DooD-with-proxy won for this stage: fastest unblock,
reuses the host's build/layer cache, and this repo already shares the host
code tree so the stack runs where it can be seen and controlled directly.

## What's wired up

`docker-compose.yml` adds two services alongside `hermes-agent`:

- **`docker-socket-proxy`** (`tecnativa/docker-socket-proxy`) — the only
  thing in this setup that mounts the real `/var/run/docker.sock`, read-only,
  and only *it* has that mount. It's deny-by-default: every Docker API group
  is off unless explicitly turned on, and only enough is on to build an
  image, run/inspect/exec into a compose stack, and tear it down
  (`CONTAINERS`, `IMAGES`, `NETWORKS`, `VOLUMES`, `BUILD`, `EXEC`, `POST`,
  `INFO`, `PING`, `VERSION`). It publishes no ports and sits on an
  `internal: true` network (`docker-proxy-net`) — nothing outside that
  network, on the host or off it, can reach it. `hermes-agent` is the only
  other thing attached to `docker-proxy-net`.
- **`docker-cli-provisioner`** (`docker:27-cli`) — the base hermes-agent
  image ships no `docker` client. This one-shot service copies the `docker`
  binary and the compose/buildx CLI plugins out of the official CLI image
  into a shared named volume (`docker-cli-bin`) once at `compose up` time,
  then exits; `hermes-agent` waits for it (`depends_on:
  service_completed_successfully`) before starting.

`hermes-agent` itself gets:

- `DOCKER_HOST=tcp://docker-socket-proxy:2375` — every `docker`/`docker
  compose` command the team runs goes through the filtered proxy, never a
  raw socket.
- The `docker-cli-bin` volume mounted read-only at `/opt/docker-cli`.
  `bootstrap.sh`/`bootstrap.ps1` (step 3b) symlink
  `/opt/docker-cli/bin/docker` → `/usr/local/bin/docker` and the CLI
  plugins into `/usr/local/libexec/docker/cli-plugins/` after the container comes
  up — idempotent, safe to re-run.
- `PROJECT_REPO_PATH` forwarded as a real env var (see the path gotcha
  below).

No socket is ever mounted into `hermes-agent`. The team already has shell
access via the `terminal` platform toolset (see each profile's
`config.yaml`), so once bootstrap has run, `docker build` / `docker compose
up` / `docker ps` etc. just work from inside the team's own container.

## The one footgun: bind-mount paths resolve on the HOST

`hermes-agent` and whatever containers the team starts (to build/run the
app's own stack) are **siblings on the host daemon** — the proxy forwards
API calls to the host engine, it doesn't create a nested one. That means
when the team runs something like:

```
docker run -v "$(pwd)":/app ...
docker compose -f some-stack.yml up
```

any bind-mount source path is resolved by the **host** daemon, not by
`hermes-agent`'s own filesystem. `pwd` inside the team's container is
`/workspace/<project>/...` — a path that means nothing to the host and will
silently bind-mount empty.

**Fix: use `$PROJECT_REPO_PATH` (forwarded into the container's environment)
instead of `pwd` or a hardcoded `/workspace/...` path when constructing a
bind mount for a sibling container.** It's the same absolute host path
`docker-compose.yml` already uses for the Tier 3 mount (see
`docs/MOUNTS.md`), so it's guaranteed to line up with what the host daemon
expects. If the team is working in a per-task git worktree under
`.worktrees/<task-id>`, the correct host path is
`$PROJECT_REPO_PATH/.worktrees/<task-id>`, not the in-container
`/workspace/<project>/.worktrees/<task-id>` path.

Builds are unaffected — `docker build` streams the build context over the
API rather than resolving a host path, so it works the same regardless of
which "side" it's invoked from.

## Keeping the host clean (self-cleaning runs)

The shared host engine has no notion of "this team's stuff" — label
whatever the team's stack creates and prune by that label rather than by
name, so runs don't accumulate orphans:

```bash
# when creating anything for a validation run:
docker run --label hermes.stack=$PROJECT_NAME ...
docker compose -f some-stack.yml -p "$PROJECT_NAME-stack" up -d

# teardown (safe to run any time, matches only this project's labeled stuff):
docker ps -aq --filter "label=hermes.stack=$PROJECT_NAME" | xargs -r docker rm -f
docker compose -f some-stack.yml -p "$PROJECT_NAME-stack" down -v
```

Using `-p "$PROJECT_NAME-stack"` as the compose project name namespaces
container/network names too, avoiding collisions if more than one team ever
shares this host.

## Reaching the running app

Whatever ports the app's own compose file publishes are reachable directly
on the host at `localhost:<port>` — same host, same daemon, no extra hop.
`docker ps` (from inside the team's container, via the proxy) shows the
real published ports for confirmation.

## Validating the wiring

From inside the team's container (`docker exec -it <project>-hermes hermes`,
or any shell with the `terminal` toolset):

```bash
docker version                 # confirms DOCKER_HOST → proxy → host daemon
docker build -t smoke-test .    # build reuses host layer cache
docker compose up -d            # brings up the sample/app stack
docker compose down -v          # tears it down, no orphans left
```

## Out of scope here

Sysbox and privileged DinD (evaluated and deferred — see the source design
doc) and any change to per-team isolation topology. Both are the
longer-term path once this moves from a single shared container to a
per-team fleet; this document only covers the current single-container
stage.
