# podman-sandbox

A rootless Podman sandbox suite for everyday Node.js development, disposable testing, and secure browser-based auditing of untrusted code.

Run workflows inside containers with configurable resource limits, restricted filesystem access, and rigorous network isolation — without giving up native Linux filesystem performance.

## Features

* **Rootless containers:** Uses rootless Podman to reduce the impact of container compromise and ensure proper UID mapping (`--userns=keep-id`).
* **Filesystem safeguards:** Rejects the filesystem root (`/`), your home directory root (`$HOME`), and hidden paths directly under your home directory (e.g., `~/.ssh`, `~/.aws`, `~/.config`).
* **Five execution modes:** Choose between normal development, disposable network testing, offline read-only inspection, restricted terminal execution, and browser-based visual code auditing.
* **Network isolation:** Restrict container networking in inspection and untrusted execution modes, or bind strictly to local loopback (`127.0.0.1`) for safe IDE UI access.
* **Resource limits:** Configure CPU, memory, and process limits for development; apply stricter defaults to restricted modes.
* **Local image verification:** Explicitly check whether required Node.js and `code-server` images are available locally before launching containers.
* **Simple installation:** Installs shell helpers with restricted file permissions and backs up shell configuration before modifying it.

## Security Models

The sandbox provides five tailored modes for different trust levels:

| Command | Filesystem | Network | Intended use |
| --- | --- | --- | --- |
| `devnode` | Repository writable (`:rw,z`) | Enabled | Trusted everyday development in your working tree |
| `testnode` | Disposable working copy (`:rw`) | Enabled | Network-enabled testing of moderately trusted code |
| `inspectrepo` | Repository read-only (`:ro`) | Disabled | Offline code inspection and auditing in the terminal |
| `untrustednode` | Repository read-only (`:ro`) | Disabled | Restricted, offline execution of untrusted code |
| `inspectide` | Repository read-only (`:ro,z`) | Local Loopback (`127.0.0.1`) | Browser-based visual audit using `code-server` |

### 1. `devnode` — Everyday Development

- Writable repository mount directly in your working tree.
- Network access for package installation and development tools.
- **Split-port mapping** on `127.0.0.1:3001` forwarding to container port `3000` (cleanly coexisting with IDE Dev Containers).
- **Persistent caching** via dedicated Podman named volumes (`pnpm_store` and `corepack_cache`) for lightning-fast dependency installs and zero host or project pollution.
- Configurable CPU, memory, and process limits with dynamic TTY and port allocation for interactive shells versus one-off CLI tasks.

> **Use this mode for projects and code you fully trust.**

### 2. `testnode` — Network-Enabled Testing (Disposable Copy)

* Archives the current repository (excluding `.git`, secrets, and local dependencies) and extracts it to a temporary host workspace.
* Network access enabled for downloading packages or running integration tests.
* Automatically cleans up and destroys the temporary workspace upon exit.

> **Use this mode when testing moderately trusted code** that requires network access but must not be allowed to modify your working tree.

### 3. `inspectrepo` — Read-Only Inspection (Terminal)

* Read-only repository mount (`:ro`).
* No container network access (`--network=none`).
* Read-only container root filesystem.
* Interactive shell for browsing and inspecting source code safely.

> **Use this mode when you want to examine a repository via CLI without allowing ordinary writes to its files.**

### 4. `untrustednode` — Restricted Execution

* Read-only repository mount (`:ro`).
* No container network access (`--network=none`).
* Read-only container root filesystem.
* Temporary writable storage for `/tmp` and a disposable home/cache.

> **Use this mode to run tests or execute code that you don't fully trust**, provided the workload doesn't require network access or repository writes.

### 5. `inspectide` — Browser-Based Visual Inspection (`code-server`)

* Read-only repository mount (`:ro,z`).
* Strictly bound to local loopback (`127.0.0.1::8080`) with dynamic ephemeral port allocation.
* Immutable root filesystem (`--read-only`) with isolated XDG state directories mapped to secure `tmpfs`.
* Renders a full VS Code interface in your browser for safe visual code review.

> **Use this mode to audit untrusted codebases visually** without risking file modifications or host contamination.

> **Important Security Note:** These modes reduce risk; they do not provide a perfect security boundary. Rootless containers still share the host kernel. Read-only mounts also do not hide files that are already present in the repository. Keep credentials, secrets, and sensitive data out of repositories used for untrusted execution.

## Requirements

* Linux with a working rootless Podman installation.
* Bash or Zsh.
* Standard command-line utilities (`grep`, `install`, `mktemp`, `tar`, `awk`).
* Container Images:
* Node.js container image: `docker.io/library/node:22-bookworm`
* Code-server container image: `docker.io/codercom/code-server:latest`



*Note: The scripts use `--pull=never`, so images must be pulled locally before running the sandbox commands.*

### Operating System Compatibility

* **Linux (Primary Target):** Native Linux containers provide direct filesystem access without the additional file-sharing layer commonly involved in VM-backed container environments.
* **macOS / Windows:** Podman can run through a virtual machine on macOS and Windows, but filesystem performance and user-namespace behavior may differ. Those environments are not the primary target of this project.

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/your-username/podman-sandbox.git
cd podman-sandbox

```

### 2. Pull Required Images

```bash
podman pull docker.io/library/node:22-bookworm
podman pull docker.io/codercom/code-server:latest

```

### 3. Install the Shell Helpers

Run the installer from the repository root:

```bash
bash install.sh

```

**What the installer does:**

* Validates the syntax of `podman-sandbox.sh` using `bash -n`.
* Creates `~/.config/podman-sandbox` with restricted permissions (`700`).
* Staged-installs and locks down the core library (`sandbox.sh` with `600` permissions).
* Detects your interactive shell (`bash` or `zsh`), backs up your existing configuration file if changes are needed, and appends the source hook idempotently.

### 4. Activate the Helpers

For Zsh:

```bash
source ~/.zshrc

```

For Bash:

```bash
source ~/.bashrc

```

*(Alternatively, open a new terminal session.)*

### 5. Verify the Installation

```bash
checknodeimg
checkcodeimg

```

This confirms that the expected image references exist in your local Podman image store.

## Usage Reference

Verify you are inside a valid project directory, then use the following commands:

### Check Image Status

```bash
checknodeimg
checkcodeimg

```

### Everyday Development (`devnode`)

```bash
devnode npm run dev

```

*Port 3000 is forwarded to the host's loopback interface.*

### Test Moderately Trusted Code (`testnode`)

```bash
testnode npm install && npm test

```

*Runs inside a disposable copy with network access; your working directory remains untouched.*

### Forensic Code Inspection (`inspectrepo`)

```bash
inspectrepo

```

*Opens an interactive read-only audit shell with zero internet access.*

### Run Untrusted Code (`untrustednode`)

```bash
untrustednode node --test

```

*Executes offline with strict read-only repository protection.*

### Visual Browser Audit (`inspectide`)

```bash
inspectide

```

*Spins up a hardened `code-server` instance and prints a secure local loopback URL (e.g., `[http://127.0.0.1:43713](http://127.0.0.1:43713)`) for safe visual inspection.*


### 6. Native IDE Integration (Dev Containers)

For everyday development where you want full IDE integration (LSPs, debuggers, and formatters) without leaving your editor, this suite supports native Dev Containers (.devcontainer/devcontainer.json).

This setup mirrors your strict security model directly inside editors like Zed or VS Code without requiring heavy SSH daemons running inside the container.
How to Set It Up in Your Project

  - Create a .devcontainer directory at the root of your Node.js project:
    Bash
    ```bash
    mkdir -p .devcontainer
    ```
  - Create a devcontainer.json file inside that folder:
    ```bash
    touch .devcontainer/devcontainer.json
    ```
  - Copy and paste the following hardened configuration into your devcontainer.json:

  ```JSON
  {
    "name": "Secure Node Dev",
    "image": "docker.io/library/node:22-bookworm",
    "remoteUser": "node",
    "runArgs": [
      "--userns=keep-id",
      "--security-opt=no-new-privileges",
      "--cap-drop=all"
    ],
    "postCreateCommand": "npm install",
    "forwardPorts": [3000]
  }
  ```

### Getting Started in Your Editor

  - VS Code / VS Codium: Open your project directory. When prompted with "Folder contains a Dev Container configuration file. Reopen folder to develop in a container", click Reopen in Container.

  - Zed: Open the project workspace. Zed will automatically detect the .devcontainer configuration and allow you to spin up the isolated development environment natively.

  - Security Note: This configuration maintains strict security parity by forcing rootless user mapping (--userns=keep-id), stripping capabilities (--cap-drop=all), and blocking privilege escalation, while automatically handling your project's npm install and port forwarding on port 3000.

### Troubleshooting: Port Collisions (CLI devnode vs. IDE Dev Containers)

If you run your terminal-based CLI devnode command concurrently with your editor's Dev Container (e.g., having both open simultaneously for testing or multi-window workflows), you may encounter host port collisions on port 3000.
  - Cause: Both the terminal CLI devnode script and your IDE container attempt to bind to the same host port (3000).
  - The Solution: Offset your CLI devnode host port mapping so it doesn't collide with your editor. For instance, mapping host port 3001 to container port 3000 (-p 127.0.0.1:3001:3000) allows your IDE Dev Container to cleanly own port 3000 while your CLI sandbox runs on port 3001.

  
## Development Resource Limits

`devnode` supports environment variables for adjusting resource limits:

| Variable | Default | Purpose |
| --- | --- | --- |
| `DEV_MEM` | `6g` | Container memory limit |
| `DEV_CPUS` | `6` | CPU limit |
| `DEV_PIDS` | `1024` | Maximum number of processes and threads |

For example:

```bash
DEV_MEM=4g DEV_CPUS=2 DEV_PIDS=512 devnode

```

## Disclaimer

Most of the code in this repository is AI-generated and has not necessarily been thoroughly security-audited. Please review both the installer and the sandbox script before installation and use.

These scripts provide defense-in-depth, but container isolation is not a guarantee against all security risks. Use the appropriate mode for your trust level, and do not use `devnode` with untrusted repositories or dependencies, as it mounts your project directory with write access, use a disposable VM instead.

Use at your own risk.
