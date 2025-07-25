package validation

import (
	"errors"
	"net"
	"regexp"
	"strconv"
	"strings"
)

// ValidateVirtualIP validates the Virtual IP address for HA configuration
func ValidateVirtualIP(value string) error {
	if len(strings.TrimSpace(value)) == 0 {
		return errors.New("virtual IP is required for HA configuration")
	}

	// Validate IP format
	ip := net.ParseIP(strings.TrimSpace(value))
	if ip == nil {
		return errors.New("virtual IP must be a valid IP address")
	}

	// Should be IPv4
	if ip.To4() == nil {
		return errors.New("virtual IP must be an IPv4 address")
	}

	return nil
}

// ValidateLoadBalancerPort validates the load balancer port (optional field)
func ValidateLoadBalancerPort(value string) error {
	trimmed := strings.TrimSpace(value)

	// Empty value is acceptable (optional field)
	if trimmed == "" {
		return nil
	}

	// Parse port number
	port, err := strconv.Atoi(trimmed)
	if err != nil {
		return errors.New("load balancer port must be a valid number")
	}

	// Port range validation
	if port < 1 || port > 65535 {
		return errors.New("load balancer port must be between 1 and 65535")
	}

	// Avoid common system ports
	if port < 1024 {
		return errors.New("load balancer port should be above 1024 to avoid system ports")
	}

	return nil
}

// ValidateEtcdSnapshotCount validates etcd snapshot count (optional field)
func ValidateEtcdSnapshotCount(value string) error {
	trimmed := strings.TrimSpace(value)

	// Empty value is acceptable (optional field)
	if trimmed == "" {
		return nil
	}

	// Parse snapshot count
	count, err := strconv.Atoi(trimmed)
	if err != nil {
		return errors.New("etcd snapshot count must be a valid number")
	}

	// Should be positive
	if count <= 0 {
		return errors.New("etcd snapshot count must be a positive number")
	}

	// Reasonable upper bound
	if count > 100000 {
		return errors.New("etcd snapshot count should be reasonable (max 100,000)")
	}

	return nil
}

// ValidateEtcdHeartbeatInterval validates etcd heartbeat interval (optional field)
func ValidateEtcdHeartbeatInterval(value string) error {
	trimmed := strings.TrimSpace(value)

	// Empty value is acceptable (optional field)
	if trimmed == "" {
		return nil
	}

	// Check if it looks like a duration (ends with time unit)
	matched, _ := regexp.MatchString(`^\d+(?:ns|us|µs|ms|s|m|h)$`, trimmed)
	if !matched {
		return errors.New("etcd heartbeat interval must be a valid duration (e.g., 100ms, 1s)")
	}

	return nil
}