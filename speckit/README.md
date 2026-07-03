# Vendored SpecKit skills (pinned)

This directory is a **generated, version-pinned** [GitHub Spec Kit](https://github.com/github/spec-kit)
install. **Do not hand-edit anything under `.claude/` or `.specify/`.** It is
committed to git so that every SpecKit upgrade is a normal, reviewable,
revertable diff — not a silent network pull at container-start.

## What's here

| Path | What it is |
|---|---|
| `.claude/skills/speckit-*/` | The `speckit-*` skills — the only part bind-mounted into the Hermes container (read-only, at `/opt/speckit-skills`, via `docker-compose.yml`). |
| `.specify/` | SpecKit's own templates, scripts, and `integrations/*.manifest.json`. The manifests record a SHA-256 for every managed skill file; they drive the drift check. Host-side only — **not** mounted into the container. |
| `CLAUDE.md` | Generated agent-context file that ships with the install. Kept for install fidelity; not mounted. |
| `SPECKIT_VERSION` | The single source of truth for the pinned version (e.g. `0.11.5`). |

## How it's wired into the container

`config/config.yaml` lists `/opt/speckit-skills` under `skills.external_dirs`,
and `docker-compose.yml` mounts `./speckit/.claude/skills` there read-only —
separate from the hand-authored `./skills` (`/opt/curated-skills`) so the
generated baseline stays visibly distinct. See `docs/MOUNTS.md`.

`bootstrap.sh` / `bootstrap.ps1` perform **no** SpecKit install, upgrade, or
network fetch. The skills are already vendored here; the container just mounts
them.

## Updating (the only supported way to change these files)

Regenerate wholesale from the pinned version — never edit skill files directly:

```bash
scripts/update-speckit-skills.sh            # regenerate at SPECKIT_VERSION
scripts/update-speckit-skills.sh 0.12.0     # bump the pin, then regenerate
```

```powershell
scripts\update-speckit-skills.ps1
scripts\update-speckit-skills.ps1 -Version 0.12.0
```

The script installs SpecKit pinned via `uvx --from git+…@v<version>`
(reproducible regardless of any globally-installed `specify`), runs
`specify init --integration claude`, swaps the output in here, and verifies it
is drift-clean. Then review `git diff speckit/` and commit.

## Drift check

`scripts/check-speckit-drift.{sh,ps1}` runs `specify integration status --json`
against this tree and fails if any managed skill file no longer matches its
recorded hash — i.e. someone hand-edited a skill instead of regenerating. It
runs in CI (`.github/workflows/speckit-drift.yml`) and can be run locally at
any time.
