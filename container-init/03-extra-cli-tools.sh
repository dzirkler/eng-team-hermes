#!/command/with-contenv sh
# shellcheck shell=sh
# Symlinks the docker + gh CLIs onto PATH at container boot.
#
# Runs as root, after 01-hermes-setup and 02-reconcile-profiles (see
# their headers — /etc/cont-init.d/* runs in lexicographic order, before
# s6-rc starts any user service). Bind-mounted read-only into the image
# at /etc/cont-init.d/03-extra-cli-tools.sh (see docker-compose.yml).
#
# Both binaries are populated into read-only volumes by one-shot sidecar
# services (docker-cli-provisioner -> /opt/docker-cli,
# gh-cli-provisioner -> /opt/gh-cli — see docker-compose.yml and
# docs/DOCKER_EXECUTION.md) that `depends_on: service_completed_successfully`
# guarantees finish before this container even starts, so both source
# paths are always present by the time this hook runs.
#
# 2026-07-05: previously bootstrap.sh/.ps1 created these symlinks via
# `docker exec` AFTER the container came up and passed its readiness
# check. That worked right after bootstrap ran, but the symlinks were
# later found missing with no restart/recreate in between (confirmed:
# same container ID, RestartCount 0, /usr/local/bin's mtime still at
# image-build time) — root cause not fully pinned, but moving this into
# the container's own guaranteed boot sequence removes the dependency on
# bootstrap's external timing entirely: it now reapplies on every start,
# recreate, or restart, with nothing bootstrap has to get right.
set -e

if [ -x /opt/docker-cli/bin/docker ]; then
    ln -sf /opt/docker-cli/bin/docker /usr/local/bin/docker
    mkdir -p /usr/local/libexec/docker/cli-plugins
    for f in /opt/docker-cli/cli-plugins/*; do
        [ -e "$f" ] && ln -sf "$f" "/usr/local/libexec/docker/cli-plugins/$(basename "$f")"
    done
fi

if [ -x /opt/gh-cli/bin/gh ]; then
    ln -sf /opt/gh-cli/bin/gh /usr/local/bin/gh
fi

true
