# ADR-003: Private Workload Git Hosting

**Status:** Accepted

**Date:** 2025-07-02

**Supersedes:** None

## Context and Problem Statement

The ZTC platform provides a robust Infrastructure-as-Code (IaC) foundation for the cluster, with its configuration managed in a central Git repository on GitHub. ArgoCD uses this repository to manage the cluster's system components and platform services.

However, end-users of the platform need a secure and private location to host the source code and deployment manifests for their own applications ("workloads"). The current model requires users to source their own Git hosting solution. This leads to several challenges:

*   **Privacy & Security:** User code, which may be sensitive or proprietary, might be stored on external, third-party platforms.
*   **Dependency:** The development and deployment lifecycle becomes dependent on the availability of external services (e.g., GitHub.com).
*   **Fragmented Experience:** Users do not have a single, unified platform for both cluster services and their own application development.
*   **Onboarding Complexity:** New users must configure repository access, deploy keys, and webhooks between their chosen Git provider and the cluster's ArgoCD instance.
*   **Contradiction of Core Principles:** Relying on external services for core development loops goes against the ZTC goal of a self-sufficient, resilient, and simple platform suitable for homelab and air-gapped environments.

To create a truly self-contained and secure development ecosystem, we need to provide a solution for private workload hosting *within* the ZTC platform itself.

## Decision Drivers

*   **Reliability (Lesson from ADR-002):** The solution must be simple and add minimal complexity to avoid introducing new failure points.
*   **Resource Constraints:** The solution must be lightweight and suitable for typical homelab hardware.
*   **Simplicity ("Zero Touch"):** The component must be easy to automate and manage.
*   **Privacy:** The primary goal is to ensure user workload code can remain within the cluster boundary.
*   **User Experience:** The solution should solve the immediate pain point of private Git hosting without overwhelming users.

## Considered Options

### Option 1: Comprehensive Platform Transformation (GitLab + Harbor)

This option involves deploying a full suite of development tools, including GitLab for source control, CI/CD, and a container registry like Harbor.

*   **Pros:**
    *   Provides a complete, all-in-one platform experience.
    *   Enables powerful, in-cluster CI/CD workflows.
*   **Cons:**
    *   **Excessive Complexity:** Directly contradicts the "reliability-first" mandate from ADR-002 by adding multiple, complex stateful systems.
    *   **High Resource Usage:** GitLab alone requires significant CPU and memory (~4GB+ RAM), making it unsuitable for most homelab environments.
    *   **Premature Optimization:** Solves problems (e.g., complex CI/CD) that the user base does not have yet, while failing to meet the primary constraint of resource efficiency.

### Option 2: Focused, Lightweight Git Hosting (Gitea)

This option involves deploying a single, lightweight Git server (Gitea) for source control hosting only.

*   **Pros:**
    *   **Extremely Lightweight:** Gitea has minimal resource requirements (~100MB RAM), making it ideal for homelabs.
    *   **Simple and Reliable:** As a single, focused component, it is far easier to manage, automate, and make resilient.
    *   **Solves the Core Problem:** Directly addresses the user need for private, self-hosted Git repositories without unnecessary feature creep.
    *   **Aligns with ZTC Philosophy:** Honors the principles of simplicity, reliability, and resource consciousness.
*   **Cons:**
    *   Does not provide an integrated CI/CD or container registry solution out-of-the-box.

## Decision

We will proceed with **Option 2: Deploy a focused, lightweight Git server (Gitea) inside the cluster.**

This decision directly aligns with our strategic goals. It solves the immediate and most critical user problem—private code hosting—while adhering strictly to the lessons learned from previous ADRs regarding reliability and complexity. It respects the resource constraints of our target homelab audience and avoids the "mission creep" of transforming ZTC into a heavyweight platform engineering suite prematurely.

## Implementation Strategy

1.  **Component Integration:** A Gitea instance will be deployed as a new system component via a Helm chart, managed within the existing `kubernetes/system/` directory structure.
2.  **Storage:** Gitea will be configured to use a reliable `StorageClass` for its Persistent Volume. A robust backup and restore strategy for this volume is a critical part of the implementation.
3.  **ArgoCD Integration:** The in-cluster Gitea will be configured as a primary, trusted Git source in ArgoCD, allowing it to manage applications from user repositories.
4.  **Documentation:** The process for using the self-hosted Gitea instance will be clearly documented as the standard, recommended workflow for private workloads.

## Consequences

### Positive Outcomes

*   **User Privacy:** User code remains within the cluster, satisfying a core requirement.
*   **Increased Resilience:** The core development loop is no longer dependent on internet connectivity or external services.
*   **Improved User Experience:** The process of starting a new private project is significantly simplified.
*   **Project Focus:** ZTC remains a lean, reliable cluster automation tool, avoiding the operational burden of a full-fledged PaaS.

### Negative Outcomes / Risks

*   **Stateful Service Management:** The platform team now owns a critical stateful service. The availability and integrity of the Gitea data (user repositories) is a new, high-priority responsibility.
*   **Backup and Recovery is Critical:** A failure to properly implement and test backups for the Gitea volume will result in permanent loss of user code.

## Future Considerations

After this lightweight solution is implemented, proven to be reliable, and has seen user adoption, we can evaluate adding more advanced features like:

*   In-cluster CI/CD runners.
*   A self-hosted container registry.
*   Automated user onboarding and workload templates.

This incremental approach allows the platform to evolve based on validated user needs and proven operational stability.