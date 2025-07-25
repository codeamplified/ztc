package validation

import (
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// ValidateSSHPublicKeyPath validates SSH public key file path
func ValidateSSHPublicKeyPath(value string) error {
	if len(strings.TrimSpace(value)) == 0 {
		return errors.New("SSH public key path is required")
	}

	// Expand tilde to home directory for validation
	expanded := expandPath(value)

	// Check if path looks like a public key path
	if !strings.HasSuffix(expanded, ".pub") && !strings.Contains(expanded, "id_") {
		return errors.New("SSH public key path should end with .pub or contain 'id_'")
	}

	// Basic path validation
	if strings.Contains(expanded, "..") {
		return errors.New("SSH public key path cannot contain '..'")
	}

	return nil
}

// ValidateSSHPrivateKeyPath validates SSH private key file path
func ValidateSSHPrivateKeyPath(value string) error {
	if len(strings.TrimSpace(value)) == 0 {
		return errors.New("SSH private key path is required")
	}

	// Expand tilde to home directory for validation
	expanded := expandPath(value)

	// Check if path looks like a private key path (should NOT end with .pub)
	if strings.HasSuffix(expanded, ".pub") {
		return errors.New("SSH private key path should not end with .pub (that's for public keys)")
	}

	// Should contain common private key patterns
	if !strings.Contains(expanded, "id_") && !strings.Contains(expanded, "ssh") {
		return errors.New("SSH private key path should contain 'id_' or 'ssh'")
	}

	// Basic path validation
	if strings.Contains(expanded, "..") {
		return errors.New("SSH private key path cannot contain '..'")
	}

	return nil
}

// ValidateSSHUsername validates SSH username
func ValidateSSHUsername(value string) error {
	if len(strings.TrimSpace(value)) == 0 {
		return errors.New("SSH username is required")
	}

	username := strings.TrimSpace(value)

	// Length validation
	if len(username) > 32 {
		return errors.New("SSH username must be 32 characters or less")
	}

	// Character validation - allow alphanumeric, underscore, hyphen
	matched, _ := regexp.MatchString("^[a-zA-Z0-9_-]+$", username)
	if !matched {
		return errors.New("SSH username can only contain letters, numbers, underscores, and hyphens")
	}

	// Cannot start with hyphen or number
	if strings.HasPrefix(username, "-") {
		return errors.New("SSH username cannot start with a hyphen")
	}
	if matched, _ := regexp.MatchString("^[0-9]", username); matched {
		return errors.New("SSH username cannot start with a number")
	}

	// Reserved usernames
	reserved := []string{"root", "admin", "administrator", "daemon", "bin", "sys", "sync", "games", "man", "lp", "mail", "news", "uucp", "proxy", "www-data", "backup", "list", "irc", "gnats", "nobody"}
	for _, reservedName := range reserved {
		if strings.ToLower(username) == reservedName {
			return errors.New("SSH username cannot be a reserved system username")
		}
	}

	return nil
}

// ExpandPath expands ~ to home directory (exported for internal use)
func ExpandPath(path string) string {
	if strings.HasPrefix(path, "~/") {
		homeDir, err := os.UserHomeDir()
		if err != nil {
			return path // Return original if we can't get home dir
		}
		return filepath.Join(homeDir, path[2:])
	}
	return path
}

// expandPath expands ~ to home directory (internal)
func expandPath(path string) string {
	if strings.HasPrefix(path, "~/") {
		homeDir, err := os.UserHomeDir()
		if err != nil {
			return path // Return original if we can't get home dir
		}
		return filepath.Join(homeDir, path[2:])
	}
	return path
}