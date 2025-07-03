# ADR-005: Automated DNS and TLS for Homelab Services

**Status:** Proposed

**Date:** 2025-07-02

**Supersedes:** N/A

## Context and Problem Statement

Currently, accessing any web service (e.g., Gitea, Vaultwarden) requires users to manually edit their local `hosts` file to map a hostname like `gitea.homelab.local` to the cluster's ingress IP address. This process is manual, error-prone, does not scale as new services are added, and is not feasible for many client devices (e.g., mobile phones, tablets).

Furthermore, services use self-signed TLS certificates, causing browsers to display prominent security warnings. This degrades the user experience and encourages poor security practices like ignoring certificate errors. The goal is to provide a seamless, secure, and automated method for accessing services from any device on the local network.

## Decision Drivers

*   **Zero Touch Operations:** The solution should minimize ongoing manual configuration for both administrators and users. New services should be exposed automatically.
*   **User Friendliness:** Accessing services should be as simple as typing `https://service-name.homelab.lan` into a browser, without security warnings or the need for client-side configuration.
*   **Security:** All web traffic, especially for services handling credentials, must be encrypted with a trusted certificate.
*   **Scalability & Maintainability:** The solution must be robust and work with the existing Kubernetes-native tooling and architecture.

## Considered Options

### Option 1: External DNS Server (Recommended)

*   **Description:** Deploy a dedicated DNS server (dnsmasq, Pi-hole, Unbound) on the storage node or separate infrastructure. Configure wildcard DNS resolution for `*.homelab.lan` pointing to the ingress controller. Keep cluster CoreDNS completely unchanged.
*   **Pros:**
    *   **Zero risk** to cluster DNS infrastructure - complete separation of concerns
    *   **Homelab-familiar** - most homelab users already run Pi-hole or similar DNS services
    *   **Resilient** - DNS works independently of cluster state (restarts, upgrades, etc.)
    *   **Standard tooling** - uses proven DNS server software with extensive documentation
    *   **Advanced features** - supports complex DNS rules, blocking, conditional forwarding
    *   **Easy troubleshooting** - standard DNS debugging tools and practices apply
*   **Cons:**
    *   Additional infrastructure component to deploy and maintain
    *   Requires basic DNS server knowledge (though typical for homelab users)

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

We will implement **Option 1: Centralized DNS (CoreDNS) with a Private CA (cert-manager)**.

This option provides the best balance of long-term user experience, security, and adherence to the "Zero Touch" principle. While it has the highest initial setup cost (requiring two one-time manual actions), it is the only solution that permanently solves the core problem in a scalable and secure manner. The friction of the one-time setup is a worthwhile trade-off for a system that "just works" for all users and services thereafter. We will use a non-reserved domain, `.homelab.lan`, to avoid conflicts with the mDNS protocol.

## Implementation Strategy

1.  **Install `cert-manager`:** Add `cert-manager` to the cluster via its official Helm chart.
2.  **Create Private CA:** Configure a `ClusterIssuer` to create and manage a self-signed CA for the `*.homelab.lan` domain.
3.  **Configure CoreDNS:**
    *   Identify the external IP address of the ingress controller.
    *   Modify the `coredns` ConfigMap in `kube-system` to add a host record for `*.homelab.lan` pointing to the ingress IP.
4.  **Expose CoreDNS:** Expose the CoreDNS service to the local network with a static IP address (e.g., via a `LoadBalancer` service).
5.  **Guide User Actions:**
    *   Provide clear, step-by-step instructions for the user to add the exposed CoreDNS IP to their router's DHCP DNS server list.
    *   Provide a script or command to extract the CA root certificate and clear instructions for importing it into their OS/browser trust store.
6.  **Update Ingresses:** Update all existing Ingress resources to use the new `cert-manager` issuer to automatically obtain valid TLS certificates.

## Consequences

### Positive Outcomes

*   Users can access all services at a stable, memorable address (`https://<service>.homelab.lan`) from any device on the network.
*   All traffic is secured with valid, trusted HTTPS, eliminating browser warnings.
*   New services deployed in the cluster will automatically be available with valid DNS and TLS without further configuration.
*   The manual and fragile `hosts` file editing process is eliminated entirely.

### Negative Outcomes / Risks

*   The initial setup requires manual intervention that is outside the scope of the project's automation (router and client device configuration). This presents a hurdle for less technical users.
*   The system's availability becomes dependent on the health of the `cert-manager` and `coredns` pods within the cluster.

## Future Considerations

*   Create a user-facing guide in the `docs` directory detailing how to perform the two required manual steps (router configuration and CA certificate import).
*   Add monitoring checks for the `cert-manager` and `coredns` services to the existing Uptime Kuma instance.
