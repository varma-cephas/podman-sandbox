## 1. Supply Chain & Reproducibility Hardening
* **Image Digest Pinning:** 
  Currently, the sandbox references `docker.io/library/node:22-bookworm` by tag. Future iterations will support pinning to an immutable cryptographic content digest (e.g., `@sha256:...`) for absolute supply chain reproducibility and protection against tag poisoning or upstream mutability.
* **Automatic Digest Verification:**
  Extend `checknodeimg` to verify the local image hash against a known signed manifest or pinned configuration variable.

## 2. Automated Testing & Quality Assurance
* **Shell Script Unit Testing:**
  Introduce test suites (using frameworks like `bats-core`) to automatically validate:
  * Directory guard behavior (verifying proper rejection of `/`, `$HOME`, and hidden paths).
  * Argument preservation and spacing (`"${@:2}"`).
  * Idempotent installer behavior and syntax checking (`bash -n`).
* **CI/CD Integration:**
  Add GitHub Actions or local CI checks to run syntax validation and mock container validation across supported Linux environments.


## 3. Ergonomics & Configuration Management
* **Optional Configuration File:**
  Support an optional `.sandboxrc` or user config file (`~/.config/podman-sandbox/config`) to allow custom default resource limits (`DEV_MEM`, `DEV_CPUS`) without requiring environment variables on every invocation.
* **Verbose / Debug Mode:**
  Add a flag (e.g., `SANDBOX_DEBUG=1`) to echo the generated `podman run` command with all security flags and volume mounts before execution for easier troubleshooting.


## 4. Advanced Isolation & Kernel Auditing
* **Seccomp Profiles:**
  Investigate custom seccomp filtering profiles to restrict dangerous system calls further inside `untrustednode` and `inspectrepo`.
* **Cgroup v2 Resource Accounting:**
  Ensure tight integration with host systemd/cgroups v2 limits for strict memory and CPU pressure handling under high-concurrency Node.js test runs.
