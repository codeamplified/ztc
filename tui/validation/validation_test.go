package validation

import (
	"testing"
)

// Test network validation functions
func TestValidateClusterName(t *testing.T) {
	tests := []struct {
		input    string
		hasError bool
	}{
		{"my-cluster", false},
		{"my_cluster", false},
		{"myCluster123", false},
		{"", true},                    // empty
		{"a-very-long-cluster-name-that-exceeds-the-fifty-character-limit", true}, // too long
		{"my cluster", true},          // contains space
		{"my@cluster", true},          // invalid character
	}

	for _, test := range tests {
		err := ValidateClusterName(test.input)
		if test.hasError && err == nil {
			t.Errorf("Expected error for input %q, but got none", test.input)
		}
		if !test.hasError && err != nil {
			t.Errorf("Expected no error for input %q, but got: %v", test.input, err)
		}
	}
}

func TestValidateNetworkSubnet(t *testing.T) {
	tests := []struct {
		input    string
		hasError bool
	}{
		{"192.168.1.0/24", false},
		{"10.0.0.0/8", false},
		{"", true},             // empty
		{"192.168.1.0", true},  // missing CIDR
		{"invalid", true},      // invalid format
	}

	for _, test := range tests {
		err := ValidateNetworkSubnet(test.input)
		if test.hasError && err == nil {
			t.Errorf("Expected error for input %q, but got none", test.input)
		}
		if !test.hasError && err != nil {
			t.Errorf("Expected no error for input %q, but got: %v", test.input, err)
		}
	}
}

func TestValidateGateway(t *testing.T) {
	tests := []struct {
		input    string
		hasError bool
	}{
		{"192.168.1.1", false},
		{"10.0.0.1", false},
		{"", true},              // empty
		{"invalid", true},       // invalid IP
		{"127.0.0.1", true},     // loopback
		{"224.0.0.1", true},     // multicast
	}

	for _, test := range tests {
		err := ValidateGateway(test.input)
		if test.hasError && err == nil {
			t.Errorf("Expected error for input %q, but got none", test.input)
		}
		if !test.hasError && err != nil {
			t.Errorf("Expected no error for input %q, but got: %v", test.input, err)
		}
	}
}

// Test SSH validation functions
func TestValidateSSHUsername(t *testing.T) {
	tests := []struct {
		input    string
		hasError bool
	}{
		{"ubuntu", false},
		{"user123", false},
		{"my-user", false},
		{"my_user", false},
		{"", true},              // empty
		{"root", true},          // reserved
		{"123user", true},       // starts with number
		{"-user", true},         // starts with hyphen
		{"user@host", true},     // invalid character
	}

	for _, test := range tests {
		err := ValidateSSHUsername(test.input)
		if test.hasError && err == nil {
			t.Errorf("Expected error for input %q, but got none", test.input)
		}
		if !test.hasError && err != nil {
			t.Errorf("Expected no error for input %q, but got: %v", test.input, err)
		}
	}
}

// Test storage validation functions
func TestValidateStorageSize(t *testing.T) {
	tests := []struct {
		input    string
		hasError bool
	}{
		{"10Gi", false},
		{"500Mi", true},         // too small
		{"2Ti", true},           // too large
		{"", true},              // empty
		{"invalid", true},       // invalid format
	}

	for _, test := range tests {
		err := ValidateStorageSize(test.input)
		if test.hasError && err == nil {
			t.Errorf("Expected error for input %q, but got none", test.input)
		}
		if !test.hasError && err != nil {
			t.Errorf("Expected no error for input %q, but got: %v", test.input, err)
		}
	}
}

// Test HA validation functions
func TestValidateVirtualIP(t *testing.T) {
	tests := []struct {
		input    string
		hasError bool
	}{
		{"192.168.1.100", false},
		{"10.0.0.100", false},
		{"", true},               // empty
		{"invalid", true},        // invalid IP
		{"::1", true},            // IPv6 not supported
	}

	for _, test := range tests {
		err := ValidateVirtualIP(test.input)
		if test.hasError && err == nil {
			t.Errorf("Expected error for input %q, but got none", test.input)
		}
		if !test.hasError && err != nil {
			t.Errorf("Expected no error for input %q, but got: %v", test.input, err)
		}
	}
}

func TestValidateLoadBalancerPort(t *testing.T) {
	tests := []struct {
		input    string
		hasError bool
	}{
		{"8080", false},
		{"", false},              // optional field
		{"80", true},             // system port
		{"99999", true},          // too high
		{"invalid", true},        // invalid number
	}

	for _, test := range tests {
		err := ValidateLoadBalancerPort(test.input)
		if test.hasError && err == nil {
			t.Errorf("Expected error for input %q, but got none", test.input)
		}
		if !test.hasError && err != nil {
			t.Errorf("Expected no error for input %q, but got: %v", test.input, err)
		}
	}
}