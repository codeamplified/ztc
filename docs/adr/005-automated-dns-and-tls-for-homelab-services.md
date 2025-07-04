# ADR-005: Automated DNS and TLS for Homelab Services

**Status:** Proposed

**Date:** 2025-07-02 (Updated: 2025-07-03)

**Supersedes:** N/A

## Context and Problem Statement

Currently, accessing any web service (e.g., Gitea, Vaultwarden) requires users to manually edit their local `hosts` file to map a hostname like `gitea.homelab.lan` to the cluster's ingress IP address. This process is manual, error-prone, does not scale as new services are added, and is not feasible for many client devices (e.g., mobile phones, tablets).

Furthermore, services use self-signed TLS certificates, causing browsers to display prominent security warnings. This degrades the user experience and encourages poor security practices like ignoring certificate errors. The goal is to provide a seamless, secure, and automated method for accessing services from any device on the local network.

## Decision Drivers

*   **Zero Touch Operations:** The solution should minimize ongoing manual configuration for both administrators and users. New services should be exposed automatically.
*   **User Friendliness:** Accessing services should be as simple as typing `https://service-name.homelab.lan` into a browser, without security warnings or the need for client-side configuration.
*   **Security:** All web traffic, especially for services handling credentials, must be encrypted with a trusted certificate.
*   **Scalability & Maintainability:** The solution must be robust and work with the existing Kubernetes-native tooling and architecture.

## Considered Options

### Option 1: External DNS Server on Storage Node (Recommended)

*   **Description:** Deploy dnsmasq on the existing storage node (k8s-storage at 192.168.50.20) using Ansible automation. Configure wildcard DNS resolution for `*.homelab.lan` pointing to the Traefik ingress controller. Keep cluster CoreDNS completely unchanged. Integrate with existing ZTC infrastructure patterns.
*   **Pros:**
    *   **Zero risk** to cluster DNS infrastructure - complete separation of concerns
    *   **Infrastructure as Code** - deployed and managed via existing Ansible playbooks
    *   **Leverages existing infrastructure** - uses dedicated storage node, no additional hardware
    *   **Resilient** - DNS works independently of cluster state (restarts, upgrades, etc.)
    *   **Lightweight** - dnsmasq uses minimal resources (~2MB RAM)
    *   **Zero Touch deployment** - included in `make infra` workflow
    *   **Homelab-optimized** - simple, reliable solution perfect for homelab scale
    *   **Easy troubleshooting** - standard DNS debugging tools and practices apply
    *   **Monitoring integration** - can be monitored via existing Uptime Kuma instance
*   **Cons:**
    *   Storage node becomes single point of failure for DNS. This risk is considered acceptable for a homelab environment, as the service (dnsmasq) is lightweight and highly stable. The risk is further addressed in 'Future Considerations' by proposing a redundant secondary DNS server.
    *   Requires basic DNS server knowledge (though dnsmasq is simple to manage)

### Option 2: CoreDNS Modification (Original Approach)

*   **Description:** Deploy `cert-manager` to create a private Certificate Authority (CA) within the cluster. Configure the cluster's existing CoreDNS instance to resolve a wildcard DNS record (`*.homelab.lan`) to the ingress controller's IP. Expose CoreDNS to the local network.
*   **Pros:**
    *   Kubernetes-native approach using existing cluster infrastructure
    *   No additional external services required
*   **Cons:**
    *   **High risk** to cluster DNS functionality - can break critical infrastructure
    *   **Chicken-and-egg problems** - DNS issues prevent container image pulls and cluster operations
    *   **Complex troubleshooting** - DNS issues affect both cluster and homelab functionality
    *   **Violates separation of concerns** - mixes cluster infrastructure with homelab services
    *   **Restart risks** - CoreDNS restarts can temporarily break both cluster and homelab DNS

### Option 3: Node-Level DNS Configuration

*   **Description:** Configure DNS resolution on each cluster node using systemd-resolved or similar host-level DNS services. Bypass cluster DNS for homelab domains.
*   **Pros:**
    *   No impact on cluster DNS infrastructure
    *   Uses battle-tested host DNS resolution
*   **Cons:**
    *   **Manual per-node configuration** - violates Infrastructure as Code principles
    *   **Not scalable** for larger clusters or dynamic node provisioning
    *   **Configuration drift** - difficult to maintain consistency across nodes

### Option 4: mDNS for DNS Resolution

*   **Description:** Use the mDNS protocol for name resolution, allowing devices to discover services using the `.local` TLD without a central DNS server.
*   **Pros:**
    *   True zero-configuration for clients; no router changes are needed.
*   **Cons:**
    *   **No wildcard support** - separate mDNS record required for every service
    *   **Operational complexity** - significant management overhead for multiple services
    *   **Protocol violations** - using `.local` for non-mDNS purposes causes conflicts

### Option 5: External Load Balancer + DNS

*   **Description:** Deploy external load balancer (HAProxy, nginx) with integrated DNS resolution, completely outside the Kubernetes cluster.
*   **Pros:**
    *   Complete separation from cluster infrastructure
    *   Professional-grade setup with advanced features
    *   Industry-standard approach for production environments
*   **Cons:**
    *   **Most complex** setup and maintenance overhead
    *   **Over-engineered** for homelab use cases
    *   **Additional infrastructure** requirements and costs

### Option 6: HTTP-Only Services

*   **Description:** Configure all services to be served over plain HTTP, disabling HTTPS entirely.
*   **Pros:**
    *   Extremely simple; avoids all certificate management complexity.
*   **Cons:**
    *   **Completely insecure** - all traffic including passwords sent in plain text
    *   **Poor user experience** - modern browsers display prominent "Not Secure" warnings
    *   **Violates security best practices** for credential-handling services

## Decision

We will implement **Option 1: External DNS Server on Storage Node**.

This approach provides the optimal balance of Zero Touch automation, security, and risk mitigation for ZTC's homelab architecture. By deploying dnsmasq on the existing storage node via Ansible, we achieve:

1. **Complete separation of concerns** - DNS infrastructure is isolated from cluster operations
2. **Infrastructure as Code compliance** - fits perfectly with ZTC's Ansible-driven approach
3. **Zero Touch deployment** - included in the standard `make infra` workflow
4. **Leverages existing infrastructure** - uses the dedicated storage node efficiently
5. **Minimal risk** - no modifications to critical cluster DNS components

The solution uses dnsmasq for its simplicity, reliability, and minimal resource footprint, making it ideal for homelab environments. Combined with cert-manager for TLS certificate management, this provides a robust, automated DNS and certificate solution that aligns with ZTC's core principles.

## Implementation Strategy

**Phased Approach:** This implementation will be delivered in two phases to minimize risk and provide incremental value:

### Phase 1: DNS Infrastructure (Immediate Value)
1.  **Pre-flight Validation:** Confirm that the chosen domain (homelab.lan) does not conflict with any existing network configurations, particularly those provided by an ISP-supplied router which may use a similar internal domain.
2.  **Create DNS Server Ansible Role:** Develop `ansible/roles/dns-server/` role to deploy and configure dnsmasq on the storage node.
3.  **Automated Configuration Generation:**
    *   Auto-detect Traefik ingress controller IP from the cluster
    *   Generate dnsmasq configuration with wildcard DNS: `*.homelab.lan -> <ingress-ip>`
    *   Configure upstream DNS servers for non-homelab queries
4.  **Deploy DNS Server:**
    *   Install dnsmasq on storage node (k8s-storage at 192.168.50.20)
    *   Configure systemd service for automatic startup
    *   Enable firewall rules for DNS traffic
5.  **Integration with ZTC Workflow:**
    *   Add DNS server deployment to main `make infra` command
    *   Add DNS status checking: `make dns-status`
6.  **User Configuration:**
    *   Provide clear documentation for configuring router DNS settings (point to 192.168.50.20)
    *   Basic DNS health checking and monitoring integration

**Phase 1 Outcome:** Users can access services via `http://service.homelab.lan` without manual hosts file editing.

### Phase 2: Certificate Management (Complete Solution)
1.  **Certificate Management:**
    *   Install `cert-manager` in the cluster via Helm chart
    *   Create private CA `ClusterIssuer` for `*.homelab.lan` domain
    *   Configure automatic certificate issuance for all ingress resources
2.  **Enhanced Integration:**
    *   Add CA certificate extraction: `make extract-ca`
    *   Update all existing ingress resources to use cert-manager
3.  **Complete User Experience:**
    *   Automated CA certificate extraction script for client device import
    *   Full HTTPS with trusted certificates

**Phase 2 Outcome:** Complete solution with `https://service.homelab.lan` and no browser security warnings.

### Benefits of Phased Approach:
*   **Risk Mitigation:** DNS changes tested independently before certificate complexity
*   **Incremental Value:** Immediate improvement to user experience with Phase 1
*   **Debugging Simplicity:** Easier to troubleshoot DNS vs certificate issues separately
*   **Rollback Strategy:** Can revert Phase 1 without affecting certificates, or vice versa

## Consequences

### Positive Outcomes

*   Users can access all services at a stable, memorable address (`https://<service>.homelab.lan`) from any device on the network.
*   All traffic is secured with valid, trusted HTTPS, eliminating browser warnings.
*   New services deployed in the cluster will automatically be available with valid DNS and TLS without further configuration.
*   The manual and fragile `hosts` file editing process is eliminated entirely.

### Negative Outcomes / Risks

*   The initial setup requires manual intervention that is outside the scope of the project's automation (router DNS configuration and client CA certificate import). This presents a hurdle for less technical users and means the User Friendliness goal is not fully met until these one-time manual steps are completed.
*   The storage node becomes a single point of failure for DNS resolution, though this is mitigated by dnsmasq's simplicity and reliability.
*   DNS availability depends on the health of the storage node, though this is separate from cluster operations and less likely to be affected by cluster maintenance.

## Future Considerations

*   Create a user-facing guide in the `docs` directory detailing how to perform the two required manual steps (router DNS configuration and CA certificate import).
*   Add monitoring checks for the dnsmasq service and cert-manager to the existing Uptime Kuma instance.
*   Consider DNS server redundancy by deploying a secondary dnsmasq instance on a worker node for high availability scenarios.
*   Evaluate integration with existing homelab DNS solutions (Pi-hole, AdGuard) for users who prefer unified DNS management.
*   Add automated DNS health checking and alerting as part of the monitoring stack.
*   Consider automatic router configuration via UPnP or DHCP option injection for truly "Zero Touch" DNS setup (though this requires router support).
