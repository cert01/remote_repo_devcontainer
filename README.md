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
Container Volume", not "Reopen in Container".** That command clones this repo
directly into a Docker volume on whichever daemon you're targeting, so the
workspace and the container always live on the same machine - which is what
makes this work identically for a local Docker Desktop/Engine and for a
remote engine reached over `DOCKER_HOST`. Plain "Reopen in Container" bind-
mounts your local checkout instead, which breaks the moment `DOCKER_HOST`
points at a different machine (see Troubleshooting).

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
   (`~/.zshrc`, `~/.bashrc`, or the WSL equivalent) - there's no local
   checkout for a `.env` file to live in, so these have to be real env vars
   VS Code can read from your shell:

   ```bash
   export GITHUB_REPO=Versent/some-project      # required, org/repo
   export PROJECT_DIR_NAME=project              # optional, defaults to "project"
   export COMPOSE_FILE_PATH=deployment/docker/docker-compose.yml  # optional, this is the default
   ```

   Open a new shell (or restart VS Code) so the exports take effect.
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
   ```
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

`DOCKER_HOST` needs to be visible both to VS Code itself (which drives the
clone-in-volume and the build) and to the Docker CLI inside the container, so
it must be a real environment variable on the host:

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
VS Code - the Docker CLI (both on the host and, via docker-outside-of-docker,
inside the container) uses the same agent.

## Repo layout

```
.devcontainer/
  devcontainer.json        # the single devcontainer definition
  scripts/
    post-create.sh          # in-container, once: gh auth + clone
    post-start.sh             # in-container, every start: status/health check
    lib/common.sh              # shared log/warn/err helpers
project/                      # created on first run - the cloned private repo (gitignored)
```

`GITHUB_REPO`, `PROJECT_DIR_NAME`, `COMPOSE_FILE_PATH` and `DOCKER_HOST` are
passed into the container as real environment variables via `containerEnv`/
`remoteEnv` in `devcontainer.json`, sourced from your host shell - there's no
`.env` file in this setup any more.

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
  `DOCKER_HOST` is exported on the host, the shell was restarted after
  exporting it, and the remote engine is reachable (VPN/network/firewall).
