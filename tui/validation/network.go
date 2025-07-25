package validation

import (
	"errors"
	"fmt"
	"net"
	"regexp"
	"strings"
)

// ValidateClusterName validates the cluster name input
func ValidateClusterName(value string) error {
	if len(value) == 0 {
		return errors.New("cluster name is required")
	}
	if len(value) > 50 {
		return errors.New("cluster name must be less than 50 characters")
	}
	// Allow alphanumeric, hyphens, and underscores
	matched, _ := regexp.MatchString("^[a-zA-Z0-9_-]+$", value)
	if !matched {
		return errors.New("cluster name can only contain letters, numbers, hyphens, and underscores")
	}
	return nil
}

// ValidateNetworkSubnet validates network subnet in CIDR notation
func ValidateNetworkSubnet(value string) error {
	if len(value) == 0 {
		return errors.New("network subnet is required")
	}
	// Parse CIDR notation
	_, _, err := net.ParseCIDR(value)
	if err != nil {
		return errors.New("invalid network subnet format (use CIDR notation like 192.168.50.0/24)")
	}
	return nil
}

// ValidateDNSDomain validates DNS domain format
func ValidateDNSDomain(value string) error {
	if len(value) == 0 {
		return errors.New("DNS domain is required")
	}
	if len(value) > 100 {
		return errors.New("DNS domain must be less than 100 characters")
	}
	// Basic domain validation
	matched, _ := regexp.MatchString(`^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`, value)
	if !matched {
		return errors.New("invalid DNS domain format (e.g., homelab.lan)")
	}
	return nil
}

// ValidateGateway validates gateway IP address
func ValidateGateway(value string) error {
	if len(value) == 0 {
		return errors.New("gateway IP is required")
	}
	// Parse IP address
	ip := net.ParseIP(value)
	if ip == nil {
		return errors.New("invalid gateway IP address")
	}
	// Check for reserved/invalid gateway IPs
	if ip.IsLoopback() || ip.IsMulticast() {
		return errors.New("gateway IP cannot be loopback or multicast")
	}
	return nil
}

// ValidatePodCIDR validates Kubernetes pod CIDR
func ValidatePodCIDR(value string) error {
	if len(value) == 0 {
		return errors.New("pod CIDR is required")
	}
	// Parse CIDR notation
	_, podNet, err := net.ParseCIDR(value)
	if err != nil {
		return errors.New("invalid pod CIDR format (use CIDR notation like 10.42.0.0/16)")
	}
	// Check for reasonable pod network size (not too small)
	ones, bits := podNet.Mask.Size()
	if ones > 24 {
		return errors.New("pod CIDR is too small (use /24 or larger network)")
	}
	// Check for RFC 1918 private networks (recommended)
	if !IsPrivateNetwork(podNet.IP) {
		return errors.New("pod CIDR should use private IP ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)")
	}
	_ = bits // Avoid unused variable warning
	return nil
}

// ValidateServiceCIDR validates Kubernetes service CIDR
func ValidateServiceCIDR(value string) error {
	if len(value) == 0 {
		return errors.New("service CIDR is required")
	}
	// Parse CIDR notation
	_, serviceNet, err := net.ParseCIDR(value)
	if err != nil {
		return errors.New("invalid service CIDR format (use CIDR notation like 10.43.0.0/16)")
	}
	// Check for reasonable service network size (not too small)
	ones, bits := serviceNet.Mask.Size()
	if ones > 24 {
		return errors.New("service CIDR is too small (use /24 or larger network)")
	}
	// Check for RFC 1918 private networks (recommended)
	if !IsPrivateNetwork(serviceNet.IP) {
		return errors.New("service CIDR should use private IP ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)")
	}
	_ = bits // Avoid unused variable warning
	return nil
}

// ValidateDNSUpstreams validates comma-separated DNS upstream servers
func ValidateDNSUpstreams(value string) error {
	// DNS upstreams are optional, but if provided should be valid IP addresses
	if len(value) == 0 {
		return nil // Optional field
	}

	// Split by comma for multiple DNS servers
	upstreams := strings.Split(value, ",")
	var validUpstreams []string

	for _, upstream := range upstreams {
		upstream = strings.TrimSpace(upstream)
		if upstream != "" {
			ip := net.ParseIP(upstream)
			if ip == nil {
				return fmt.Errorf("invalid DNS upstream IP address: %s", upstream)
			}
			// Check for invalid DNS server IPs
			if ip.IsLoopback() && upstream != "127.0.0.1" {
				return fmt.Errorf("DNS upstream %s: loopback addresses other than 127.0.0.1 not recommended", upstream)
			}
			if ip.IsMulticast() {
				return fmt.Errorf("DNS upstream %s: multicast addresses not allowed", upstream)
			}
			validUpstreams = append(validUpstreams, upstream)
		}
	}

	// Check for reasonable number of DNS servers
	if len(validUpstreams) > 5 {
		return errors.New("too many DNS upstreams (maximum 5 recommended)")
	}

	return nil
}

// IsPrivateNetwork checks if IP is in private network ranges (RFC 1918)
func IsPrivateNetwork(ip net.IP) bool {
	// 10.0.0.0/8
	if ip4 := ip.To4(); ip4 != nil {
		if ip4[0] == 10 {
			return true
		}
		// 172.16.0.0/12
		if ip4[0] == 172 && ip4[1] >= 16 && ip4[1] <= 31 {
			return true
		}
		// 192.168.0.0/16
		if ip4[0] == 192 && ip4[1] == 168 {
			return true
		}
	}
	return false
}

// ValidateNetworkOverlaps checks for overlapping network ranges
func ValidateNetworkOverlaps(subnet, podCIDR, serviceCIDR string) error {
	if subnet == "" || podCIDR == "" || serviceCIDR == "" {
		return nil // Skip validation if any field is empty
	}

	// Parse all networks
	_, subnetNet, err := net.ParseCIDR(subnet)
	if err != nil {
		return nil // Individual validation will catch this
	}

	_, podNet, err := net.ParseCIDR(podCIDR)
	if err != nil {
		return nil // Individual validation will catch this
	}

	_, serviceNet, err := net.ParseCIDR(serviceCIDR)
	if err != nil {
		return nil // Individual validation will catch this
	}

	// Check for overlaps
	if NetworksOverlap(subnetNet, podNet) {
		return errors.New("pod CIDR overlaps with network subnet")
	}
	if NetworksOverlap(subnetNet, serviceNet) {
		return errors.New("service CIDR overlaps with network subnet")
	}
	if NetworksOverlap(podNet, serviceNet) {
		return errors.New("pod CIDR and service CIDR overlap")
	}

	return nil
}

// NetworksOverlap checks if two network ranges overlap
func NetworksOverlap(net1, net2 *net.IPNet) bool {
	return net1.Contains(net2.IP) || net2.Contains(net1.IP)
}

// ValidateGatewayInSubnet checks if gateway IP is within the network subnet
func ValidateGatewayInSubnet(gateway, subnet string) error {
	if gateway == "" || subnet == "" {
		return nil // Skip validation if fields are empty
	}

	gwIP := net.ParseIP(gateway)
	if gwIP == nil {
		return nil // Individual validation will catch this
	}

	_, subnetNet, err := net.ParseCIDR(subnet)
	if err != nil {
		return nil // Individual validation will catch this
	}

	if !subnetNet.Contains(gwIP) {
		return errors.New("gateway IP must be within the network subnet")
	}

	return nil
}