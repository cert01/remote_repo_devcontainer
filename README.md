# v-bus devcontainer bootstrap

This folder is a self-contained VS Code devcontainer bootstrap. Opening it in a
container:

1. Installs Git, the GitHub CLI, Docker CLI/Compose (docker-outside-of-docker),
   Node.js, Go/Java/Python toolchains, and the Claude Code CLI + VS Code
   extension.
2. Logs you into GitHub (device code flow) if you aren't already.
3. Clones a private GitHub repo into `./project`.
4. Leaves you inside that one container to develop the project directly. The
   project's own `docker-compose.yml` (under `deployment/docker/` by default)
   is run with `docker compose`, as sibling containers reachable through the
   Docker socket that's forwarded in - not nested devcontainers.

Docker can be the local Docker Desktop/Engine, or a remote engine, controlled
by `DOCKER_HOST`.

**This bootstrap is opened via "Dev Containers: Clone Repository in Named
Container Volume", not "Reopen in Container".**

That command clones this repo directly into a Docker volume on whichever daemon
you're targeting, so the workspace and the container always live on the same
machine - which is what makes this work identically for a local Docker
Desktop/Engine and for a remote engine reached over `DOCKER_HOST`. Plain
"Reopen in Container" bind-mounts your local checkout instead, which breaks the
moment `DOCKER_HOST` points at a different machine (see Troubleshooting).

## Prerequisites

- VS Code with the **Dev Containers** extension.
- This folder pushed to a git remote (e.g. a private GitHub repo) - the
  clone-in-volume command clones from a URL, so it can't work on an
  uncommitted local folder.
- Docker:
  - **macOS**: Docker Desktop.
  - **Linux**: Docker Engine.
  - **Windows**: Docker Desktop with the WSL2 backend.
  - Or a remote Docker engine - see "Using a remote Docker instance" below.
- Access to the private project repo on GitHub (an account that will be
  authorised via `gh auth login` on first run).

## First-time setup

1. Export the required environment variables in your **host** shell profile
   (`~/.zshrc`, `~/.bashrc`, or the WSL equivalent) - at container-creation
   time there's no local checkout yet for a host-side script to read, so
   `${localEnv:...}` needs these as real env vars VS Code can read from your
   shell:

   ```bash
   export GITHUB_REPO=Versent/some-project      # required, org/repo
   export PROJECT_DIR_NAME=project              # optional, defaults to "project"
   export COMPOSE_FILE_PATH=deployment/docker/docker-compose.yml  # optional, this is the default
   ```

   Open a new shell (or restart VS Code) so the exports take effect.

   If you skip this, `postCreateCommand` prompts for whichever of the three
   are still unset the first time it runs inside the container, and saves
   your answers to a gitignored `.env` in the workspace so you're only asked
   once per container volume (see "Repo layout" below).
2. If you're targeting a remote Docker engine, export `DOCKER_HOST` too and
   confirm it's reachable - see "Using a remote Docker instance" below.
3. **Command Palette -> Dev Containers: Clone Repository in Named Container
   Volume**, and give it this bootstrap repo's URL (add a branch/subfolder if
   needed). VS Code clones it into a volume on the target daemon and builds
   the container from its `.devcontainer/devcontainer.json`.
4. On first build, a terminal will prompt you to authenticate with GitHub:
   open the URL shown and enter the one-time code. If the prompt doesn't
   appear or the flow is interrupted, run `gh auth login` manually in an
   in-container terminal, then `bash .devcontainer/scripts/post-create.sh`
   to retry the clone.
5. Once cloned, bring up the project's supporting services:

   ```shell
   docker compose -f project/deployment/docker/docker-compose.yml up -d
   ```

   (adjust the path if you changed `COMPOSE_FILE_PATH`). Develop against
   `./project` directly in this container - Go/Java/Python/Node tooling and
   Claude Code are already installed.

Note that the workspace is a Docker volume, not a folder on your Mac/PC - you
won't see it in Finder/Explorer. Work in it through the VS Code window
connected to the container (or `docker exec`/`docker cp` against the volume
if you ever need out-of-band access).

## Using a remote Docker instance instead of local

`DOCKER_HOST` is a **host-only** variable - it only needs to be visible to VS
Code itself (which drives the clone-in-volume and the build), never inside
the container:

```bash
# in your shell profile (~/.zshrc, ~/.bashrc, or the WSL equivalent)
export DOCKER_HOST=ssh://user@remote-host      # over SSH
# or
export DOCKER_HOST=tcp://remote-host:2376      # TCP, normally with TLS - see your engine's docs
```

Open a new shell (so the export takes effect) before launching VS Code /
running "Clone Repository in Named Container Volume". Alternatively, use a
named Docker context:

```bash
docker context create remote --docker "host=ssh://user@remote-host"
docker context use remote
```

Whichever engine is active when you run the clone-in-volume command is where
the volume and the container end up - there's no separate host/remote split
to worry about beyond that, because the workspace is never bind-mounted from
your Mac/PC in the first place.

If your remote engine is reached over SSH and needs key-based auth, make sure
your SSH agent is running and has the key loaded (`ssh-add -l`) before opening
VS Code - that's what lets VS Code's own Docker CLI create the volume and
container on the remote engine in the first place.

`devcontainer.json` deliberately does **not** forward `DOCKER_HOST` into the
container. `docker-outside-of-docker` bind-mounts `docker.sock` from whichever
engine actually creates the container - local or remote - so the in-container
`docker`/`docker compose` CLI already talks to the right daemon with no
further config, and the feature's own entrypoint handles the socket
permissions for you. If `DOCKER_HOST` were also set inside the container, the
CLI there would ignore that working local socket and instead try to open a
*new* SSH/TCP connection back out to the remote engine - a hop the container
has no credentials for, which fails with something like `Permission denied
(publickey,password)` (see Troubleshooting).

## Resetting the remote Docker engine

This wipes Docker state on whichever engine `DOCKER_HOST` (or the active
`docker context`) currently points at - useful for clearing a disposable
remote test host between runs. Run it from your **host** shell, not inside
the container.

It stops and removes every container, deletes every image, and prunes the
full build cache on that engine. It does **not** touch volumes - your cloned
workspace (the named container volume) is unaffected, so it's safe to run
between test cycles without losing that checkout. Because it's scoped by
whatever engine `DOCKER_HOST`/the active context currently resolves to, not
by project, it will also remove anything else running on that engine - only
run it against a host you know is dedicated to this kind of testing.

```bash
#!/usr/bin/env bash
# reset-remote-docker.sh - stop/remove all containers, images, and build
# cache on the Docker engine DOCKER_HOST (or the active context) points at.
set -euo pipefail

target="${DOCKER_HOST:-$(docker context inspect -f '{{.Endpoints.docker.Host}}' 2>/dev/null || echo 'default local context')}"

echo "This will stop/remove ALL containers, ALL images, and the full build cache on:"
echo "  $target"
read -r -p "Type 'yes' to continue: " confirm
[ "$confirm" = "yes" ] || { echo "Aborted."; exit 1; }

mapfile -t containers < <(docker ps -aq)
if [ "${#containers[@]}" -gt 0 ]; then
  echo "Stopping and removing ${#containers[@]} container(s)..."
  docker stop "${containers[@]}"
  docker rm "${containers[@]}"
fi

mapfile -t images < <(docker images -aq)
if [ "${#images[@]}" -gt 0 ]; then
  echo "Removing ${#images[@]} image(s)..."
  docker rmi -f "${images[@]}"
fi

echo "Pruning build cache..."
docker builder prune -af

echo "Done. Remaining disk usage on $target:"
docker system df
```

Save it as e.g. `reset-remote-docker.sh`, `chmod +x` it, confirm `DOCKER_HOST`
(or `docker context ls`) is pointed at the right engine, then run it.

## Repo layout

```text
.devcontainer/
  devcontainer.json        # the single devcontainer definition
  scripts/
    post-create.sh          # in-container, once: gh auth + clone
    post-start.sh             # in-container, every start: status/health check
    lib/common.sh              # shared log/warn/err/env helpers
.env                           # created on first run if needed - your answers (gitignored)
project/                      # created on first run - the cloned private repo (gitignored)
```

`GITHUB_REPO`, `PROJECT_DIR_NAME` and `COMPOSE_FILE_PATH` are normally passed
into the container as real environment variables via `containerEnv` in
`devcontainer.json`, sourced from your host shell. If they aren't set that
way, `post-create.sh` prompts for them on first run and writes the answers to
a gitignored `.env` in the workspace; `post-start.sh` sources that file on
every start so you're only asked once per container volume. `DOCKER_HOST` is
different: it's a host-only variable (see "Using a remote Docker instance"
above) that's never passed into the container at all, so it has no `.env`
fallback and no in-container prompt.

## Troubleshooting

- **`invalid mount config for type "bind": bind source path does not exist`
  on container creation**: you (or a script) used "Reopen in Container"
  instead of "Clone Repository in Named Container Volume" while `DOCKER_HOST`
  pointed at a remote engine. VS Code bind-mounts whatever local folder you
  have open, and that path doesn't exist on a remote daemon's machine - it's
  not fixable via devcontainer.json config. Use the clone-in-volume command
  instead (see First-time setup).
- **`gh auth login` hangs or the device code prompt never appears**: run it
  manually in a terminal inside the container, then re-run
  `bash .devcontainer/scripts/post-create.sh`.
- **Clone fails with a permissions error**: confirm the authenticated GitHub
  account actually has access to `GITHUB_REPO`, and that the exported value
  is exactly `org/repo`.
- **`GITHUB_REPO`/etc. show up empty inside the container**: these are only
  picked up from your **host** shell profile at container-creation time via
  `${localEnv:...}` - confirm they're exported before VS Code starts the
  clone/build, then rebuild the container (Dev Containers: Rebuild Container)
  after changing them.
- **Docker unreachable**: check `docker info` inside the container. For local
  Docker, confirm Docker Desktop/Engine is running. For remote, confirm
  `DOCKER_HOST` was exported on the host (and the shell restarted) *before*
  the container was created, and that the remote engine is reachable
  (VPN/network/firewall) - see "Using a remote Docker instance" above.
- **`docker compose` inside the container fails with `error during connect:
  ... command [ssh ... dial-stdio] has exited with exit status 255`, ending in
  `Permission denied (publickey,password)`**: something is exporting
  `DOCKER_HOST` inside the container itself (e.g. it got added back to
  `remoteEnv` in `devcontainer.json`, or set in a shell profile inside the
  container/volume). That makes the in-container Docker CLI try to open a new
  SSH connection back out to the remote engine instead of using the
  bind-mounted `docker.sock` that `docker-outside-of-docker` already wired up,
  and the container has no SSH key for that hop. Remove `DOCKER_HOST` from
  the container's environment - it belongs on the host only (see "Using a
  remote Docker instance" above).
- **Switching an existing window into the container closes your local VS
  Code session**: selecting a Dev Containers command that reopens the
  current window inside the volume (e.g. "Reopen in Named Volume
  Container") replaces that window in place - it doesn't open a second one.
  Any local terminals or extension sessions attached to that window,
  including a running Claude Code CLI session, are closed with it, not
  moved into the container. Finish or save that work first, and start
  Claude Code fresh once you're inside the container if you need it there.
