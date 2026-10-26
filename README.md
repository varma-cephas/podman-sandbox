# podman-sandbox

A rootless Podman sandbox for everyday Node.js development and safer execution of untrusted code.

Run Node.js workflows inside containers with configurable resource limits, restricted filesystem access, and optional network isolation — without giving up native Linux filesystem performance.

## Features

* **Rootless containers:** Uses rootless Podman to reduce the impact of container compromise.
* **Filesystem safeguards:** Rejects the filesystem root (`/`), your home directory root (`$HOME`), and hidden paths directly under your home directory (e.g., `~/.ssh`, `~/.aws`, `~/.config`).
* **Four execution modes:** Choose between normal development, disposable network testing, read-only inspection, and restricted execution.
* **Network isolation:** Disable container networking in inspection and untrusted execution modes.
* **Resource limits:** Configure CPU and memory limits for development; apply stricter defaults to restricted modes.
* **Local image verification:** Check whether the required Node.js image is available before launching a container.
* **Simple installation:** Installs shell helpers with restricted file permissions and backs up shell configuration before modifying it.

## Security Model & Workflows

The sandbox provides four tailored modes for different trust levels:

| Command | Filesystem | Network | Intended use |
| :--- | :--- | :--- | :--- |
| `devnode` | Repository writable (`:rw`) | Enabled | Trusted everyday development in your working tree |
| `testnode` | Disposable working copy (`:rw`) | Enabled | Network-enabled testing of moderately trusted code |
| `inspectrepo` | Repository read-only (`:ro`) | Disabled | Offline code inspection and auditing |
| `untrustednode` | Repository read-only (`:ro`) | Disabled | Restricted, offline execution of untrusted code |

### 1. `devnode` — Everyday Development
* Writable repository mount directly in your working tree.
* Network access for package installation and development tools.
* Local port forwarding on `127.0.0.1:3000`.
* Configurable CPU, memory, and process limits.
> **Use this mode for projects and code you fully trust.**

### 2. `testnode` — Network-Enabled Testing (Disposable Copy)
* Archives the current repository (excluding `.git`, secrets, and local dependencies) and extracts it to a secure, temporary host workspace.
* Network access enabled for downloading packages or running integration tests.
* Automatically cleans up and destroys the temporary workspace upon exit.
> **Use this mode when testing moderately trusted code** that requires network access but must not be allowed to modify your working tree.

### 3. `inspectrepo` — Read-Only Inspection
* Read-only repository mount (`:ro`).
* No container network access (`--network=none`).
* Read-only container root filesystem.
* Interactive shell for browsing and inspecting source code safely.
> **Use this mode when you want to examine a repository without allowing ordinary writes to its files.**

### 4. `untrustednode` — Restricted Execution
* Read-only repository mount (`:ro`).
* No container network access (`--network=none`).
* Read-only container root filesystem.
* Temporary writable storage for `/tmp` and a disposable home/cache.
> **Use this mode to run tests or execute code that you don't fully trust**, provided the workload doesn't require network access or repository writes.

> **Important Security Note:** These modes reduce risk; they do not provide a perfect security boundary. Rootless containers still share the host kernel. Read-only mounts also do not hide files that are already present in the repository. Keep credentials, secrets, and sensitive data out of repositories used for untrusted execution.

## Requirements

* Linux with a working rootless Podman installation.
* Bash or Zsh.
* Standard command-line utilities (`grep`, `install`, `mktemp`, `tar`).
* The Node.js container image `docker.io/library/node:22-bookworm`.

*Note: The scripts use `--pull=never`, so the image must be available locally before running the sandbox commands.*

### Operating System Compatibility

* **Linux (Primary Target):** Native Linux containers provide direct filesystem access without the additional file-sharing layer commonly involved in VM-backed container environments.
* **macOS / Windows:** Podman can run through a virtual machine on macOS and Windows, but filesystem performance and user-namespace behavior may differ. Those environments are not the primary target of this project.


## Installation

### 1. Clone the Repository
```bash
git clone [https://github.com/your-username/podman-sandbox.git](https://github.com/your-username/podman-sandbox.git)
cd podman-sandbox

```

### 2. Pull the Node.js Image

```bash
podman pull docker.io/library/node:22-bookworm

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
```

This confirms that the expected image reference exists in the local Podman image store.

## Usage Reference

Verify you are inside a valid Node.js project directory, then use the following commands:

### Check Image Status

```bash
checknodeimg
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

These scripts provide defense-in-depth, but container isolation is not a guarantee against all security risks. Use the appropriate mode for your trust level, and do not use devnode with untrusted repositories or dependencies, as it mounts your project directory with write access.

Use at your own risk.
