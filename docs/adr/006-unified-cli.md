Of course. Here is a detailed Architecture Decision Record (ADR) for the creation of the `ztc` CLI in Python, following the recommended SDK-based hybrid approach.

---

### **ADR-001: A Unified Python CLI (`ztc`) for User Experience Enhancement**

**Date:** 2023-10-27

**Status:** Proposed

#### **Context**

The Zero Touch Cluster (ZTC) project currently relies on a `Makefile` as its primary user interface. This provides powerful orchestration of underlying tools (`ansible-playbook`, `helm`, `kubectl`) but presents several user experience challenges:

*   **High Cognitive Load:** Users must understand the correct sequence of commands, which variables to pass (`DEVICE=`, `NODE=`), and which configuration files to edit manually.
*   **Poor Feedback:** Long-running operations provide raw, verbose output from the underlying tools, making it difficult to track progress or identify key information.
*   **Opaque Errors:** Failures in sub-tools (e.g., Ansible) result in cryptic stack traces that are unhelpful for users not expert in that specific tool.
*   **Inconsistent Configuration:** Configuration is spread across multiple files in different formats (Ansible inventory, `group_vars`, Helm `values.yaml`, etc.), making customization error-prone.
*   **Dependency Management:** Users are required to manually install and manage a specific set of CLI tools (`ansible`, `helm`, `kubectl`, `gpg`, etc.) on their host machine.

The project's objective is to deliver a more intuitive, guided, and feedback-rich interaction model that abstracts this complexity, making the project more accessible while retaining power for advanced users.

#### **Decision**

We will design and implement a new, unified Command-Line Interface (CLI) application named `ztc`. This application will serve as the primary, user-facing entry point for all cluster lifecycle operations.

This CLI will be implemented in **Python** and will adopt a **hybrid SDK-first approach**:

1.  **Python as the Core Language:** The `ztc` CLI will be a Python application, leveraging its rich ecosystem for creating interactive and user-friendly terminal applications.
2.  **Native SDK for Ansible:** All Ansible playbook execution will be handled programmatically using the official `ansible-runner` Python library. This replaces wrapping the `ansible-playbook` command-line tool.
3.  **Native SDK for Kubernetes:** All interactions with the Kubernetes cluster (e.g., checking node status, verifying deployments) will be performed using the official `kubernetes` Python client library. This replaces wrapping the `kubectl` command-line tool.
4.  **CLI Wrapper for Helm:** Due to the lack of a stable, official Helm SDK for Python, `ztc` will continue to wrap the `helm` command-line binary as a subprocess. This is a pragmatic compromise to retain Helm's robust release management capabilities without re-implementing its logic.
5.  **Centralized Configuration:** A new `ztc-config.yaml` file will be introduced as the single source of truth for user-defined configurations. The `ztc` tool will be responsible for reading this file and generating the necessary tool-specific configuration files (e.g., Ansible inventory, Helm values files) on the fly.

#### **Consequences**

**Positive:**

*   **Dramatically Simplified User Onboarding:** The list of user-managed dependencies is reduced from (`ansible`, `kubectl`, `helm`, etc.) to just **`helm`**. The `ztc` Python package, installed via `pip`, will manage its own `ansible-runner` and `kubernetes` client dependencies within a virtual environment.
*   **Superior User Experience:**
    *   **Guided Setup:** An interactive `ztc setup` wizard will guide users through initial configuration, eliminating manual file editing.
    *   **Enhanced Feedback:** By hooking into the `ansible-runner` event stream and using libraries like **Rich**, we can provide live progress bars, spinners, and clearly delineated status updates for long-running tasks.
    *   **Actionable Error Messages:** We can catch specific Python exceptions from the SDKs (e.g., `kubernetes.client.ApiException`) and present human-readable, context-aware error messages with suggested remedies, instead of raw stack traces.
*   **Increased Robustness and Maintainability:**
    *   **Structured Data:** Interacting with SDKs provides structured Python objects (not strings), eliminating fragile text parsing and enabling more reliable logic.
    *   **Idempotency:** The `ztc config generate` step ensures that running commands multiple times produces a consistent state based on the central `ztc-config.yaml`.
    *   **Modularity:** The CLI structure (using a framework like **Typer**) promotes clean, modular, and extensible code.
*   **Centralized and Simplified Customization:** Users can modify cluster parameters via simple commands (e.g., `ztc config set <key> <value>`) or by editing a single, well-documented `ztc-config.yaml` file.

**Negative / Risks:**

*   **One Remaining External Dependency:** The `helm` binary remains a prerequisite for the user to install. The `ztc` tool must implement a robust pre-flight check to verify its existence and guide the user on installation if it's missing.
*   **Increased Application Complexity:** The `ztc` codebase will be more complex than a simple `Makefile`, as it now contains logic for API interaction, state management, and configuration generation. This is a deliberate trade-off for the UX benefits.
*   **Potential Obfuscation for Power Users:** Advanced users familiar with the underlying tools might initially find the abstraction layer cumbersome. This will be mitigated by:
    1.  Providing a `--verbose` flag to expose the raw output from underlying processes.
    2.  Maintaining clear documentation on how `ztc` maps to the underlying tool commands.
    3.  Keeping the underlying playbooks and charts accessible for direct use if needed (e.g., via a developer-focused `Makefile`).

#### **Technical Stack Rationale**

*   **Language:** **Python**. Chosen for its excellent CLI/UX libraries, data handling capabilities, and native integration with Ansible.
*   **CLI Framework:** **Typer**. Chosen for its modern, type-hint-based approach which leads to self-documenting, easy-to-maintain code. It builds on Click, providing a solid foundation.
*   **UI/Feedback Library:** **Rich**. Chosen for its best-in-class ability to create beautiful and informative terminal UIs, including progress bars, tables, styled text, and formatted tracebacks.
*   **Configuration Parsing:** **ruamel.yaml**. Chosen over standard PyYAML for its ability to parse and write YAML files while preserving comments and formatting, which is crucial for safely modifying the user-managed `ztc-config.yaml`.
*   **Interactive Prompts:** **questionary** or **InquirerPy**. Chosen for creating user-friendly, interactive prompts for the setup wizard.

#### **Alternative Considered: Go-based CLI**

*   **Description:** A single, compiled Go binary that uses native Go SDKs for Kubernetes and Helm, but would be forced to wrap the `ansible-playbook` CLI tool.
*   **Pros:** Produces a single, portable binary; excellent native SDKs for Helm and Kubernetes.
*   **Cons:** Fails to solve the most significant dependency problem (Ansible), forcing the user to install and manage a separate Python environment. The UX/CLI development ecosystem in Python is currently more mature and faster to iterate with for this type of application.
*   **Reason for Rejection:** This approach increases the overall system complexity from a user's perspective (managing both a Go binary and a Python environment) and prevents deep, native integration with Ansible, which is a core part of the automation stack. The Python-first approach provides a more holistic and user-friendly solution by tackling the most complex dependencies natively.