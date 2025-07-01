# ADR-001: Secure and User-Friendly Secrets Management

**Status:** Accepted

**Date:** 2025-07-01

## Context

The initial version of the Zero Touch Cluster (ZTC) project handled secrets by providing `.template` files. Users were instructed to copy these templates, fill in their plaintext secrets (like Grafana passwords or Git credentials), and rely on `.gitignore` to prevent them from being committed to version control.

This approach, while simple, presented several critical issues identified during a project review:

1.  **Security Risk:** Storing plaintext secrets on disk, even if git-ignored, is a significant security vulnerability. It does not align with the project's "production-ready" claim.
2.  **Backup and Recovery:** Since secrets were not version-controlled, they were difficult to back up. A failure of the control machine could lead to a complete loss of all credentials, requiring a manual and error-prone recovery process.
3.  **Poor User Experience:** The manual process of copying, renaming, and editing multiple files was tedious and intimidating for new users. This increased the likelihood of misconfiguration.
4.  **Lack of Guardrails:** A user could accidentally remove a secret file from `.gitignore` and commit it to a public repository.

A new solution was required to address these issues, with the dual goals of making the system **more secure** and **more user-friendly**.

## Decision

We will implement a new, robust secrets management strategy built on three pillars:

1.  **Technology-Driven Security:** We will adopt a hybrid approach using best-in-class, standard tools for different secret types.
    *   **Kubernetes Secrets:** All secrets destined for the Kubernetes cluster (e.g., Grafana passwords, ArgoCD credentials, application secrets) will be encrypted using **Sealed Secrets**. This allows us to safely commit encrypted secret manifests (`SealedSecret` resources) to Git.
    *   **Infrastructure Secrets:** Secrets required by Ansible during node provisioning (e.g., credentials in `inventory/secrets.yml`) will continue to be encrypted using **Ansible Vault**.
    *   **Developer Credentials:** Sensitive developer credentials like the SSH private key and the Ansible Vault password will remain outside the repository, managed by the user on their control machine.

2.  **User-Experience-Driven Abstraction:** All complexity of the underlying tools will be abstracted away behind a simple, interactive `Makefile` interface. Users will not need to be experts in Sealed Secrets or Ansible Vault to use the system securely.

3.  **Built-in Guardrails and Sensible Defaults:** The system will be designed to prevent common mistakes and provide a smooth on-ramp for new users.

## Consequences

This decision results in a significantly improved architecture for secrets management, detailed below.

### Pillar 1: The Interactive `make setup` Wizard

The manual, multi-file editing process is replaced by a single, interactive command: `make setup`.

**Workflow:**
1.  A new user runs `make setup`.
2.  The command triggers a script that interactively prompts the user for all necessary secrets.
3.  It provides sensible defaults and can auto-generate secure passwords where appropriate.
4.  Based on the user's input, the script automatically generates all necessary secret files in their correct, encrypted formats (`SealedSecret` for Kubernetes, `ansible-vault` encrypted for Ansible).
5.  The user never directly edits a YAML secret file.

**Benefits:**
*   **Simplicity:** Reduces the setup process to a single command and a simple Q&A.
*   **Reduced Errors:** Eliminates the risk of syntax errors or misconfigurations from manual editing.
*   **Enhanced Security:** Ensures secrets are encrypted correctly from the very beginning.

### Pillar 2: The "One-Command" Backup & Recovery System

To solve the critical backup and recovery problem, we introduce two new `Makefile` targets.

*   **`make backup-secrets`:**
    *   This command locates the two "crown jewels" of the cluster's identity: the **Sealed Secrets private key** (which can decrypt all Kubernetes secrets) and the **encrypted Ansible Vault secrets file**.
    *   It bundles them into a single, timestamped, password-protected archive (e.g., `ztc-secrets-backup-2025-07-01.tar.gz.gpg`).
    *   It instructs the user to copy this **single file** to a safe, offline location.

*   **`make recover-secrets`:**
    *   This command prompts the user for their backup file and its password.
    *   It automatically decrypts the archive and restores both the Sealed Secrets key to the cluster and the Ansible secrets to the correct location on the control machine.

**Benefits:**
*   **Tangible Backup:** The abstract concept of "backing up secrets" becomes a simple, concrete action: "protect this one file."
*   **Robust Recovery:** Provides a clear, tested path to full recovery after a control machine failure or complete cluster rebuild.

### Pillar 3: Sensible Defaults & Built-in Guardrails

To make the system more forgiving and accessible, we will implement two key features.

1.  **Pre-Commit Hooks for Security:**
    *   The project will integrate with `pre-commit` and a secrets-detection tool (e.g., `detect-secrets`).
    *   The `make setup` wizard will offer to install this hook locally for the user.
    *   If a user accidentally adds a plaintext secret to a file and tries to commit it, the hook will **automatically block the commit** and warn the user, preventing catastrophic mistakes.

2.  **Default to a Local "Example Workloads" App:**
    *   To lower the initial barrier to entry, the default ArgoCD application will point to a local directory within the project (`kubernetes/example-workloads`) instead of requiring the user to immediately create a private Git repository.
    *   This allows a new user to have a fully functional cluster with a deployed "hello-world" application immediately after running `make infra`.
    *   Documentation will guide them on how to "graduate" to a full GitOps workflow with their own private repository when they are ready.

### New User Journey

The resulting user journey becomes dramatically simpler and more secure:

1.  `git clone https://github.com/codeamplified/ztc`
2.  `make setup` (Interactive wizard for configuration).
3.  `make autoinstall-usb ...` (Provision nodes as before).
4.  `make infra` (Deploy the cluster; a sample app is deployed automatically).
5.  `make backup-secrets` (Create the single, vital backup file).

This new workflow transforms secrets management from a liability into a secure, user-friendly, and robust feature of the Zero Touch Cluster project.
