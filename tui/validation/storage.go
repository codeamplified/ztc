package validation

import (
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// ValidateReplicaCount validates Longhorn replica count
func ValidateReplicaCount(value string) error {
	if value == "" {
		return errors.New("replica count is required")
	}

	count, err := parseReplicaCount(value)
	if err != nil {
		return fmt.Errorf("invalid replica count: %w", err)
	}

	if count < 1 || count > 10 {
		return errors.New("replica count must be between 1 and 10")
	}

	// Additional validation: odd numbers recommended for quorum
	if count%2 == 0 && count > 2 {
		return fmt.Errorf("replica count %d: odd numbers recommended for better quorum (try %d or %d)", count, count-1, count+1)
	}

	return nil
}

// ValidateStorageSize validates storage size with capacity requirements
func ValidateStorageSize(value string) error {
	if value == "" {
		return errors.New("storage size is required")
	}

	// Use the enhanced storage capacity validation
	if err := ValidateStorageCapacity(value); err != nil {
		return err
	}

	return nil
}

// ValidatePath validates file system paths
func ValidatePath(value string) error {
	if value == "" {
		return nil // Optional field
	}

	// Basic path validation
	if !strings.HasPrefix(value, "/") {
		return errors.New("path must start with /")
	}

	return nil
}

// ValidateStorageCapacity validates storage capacity requirements
func ValidateStorageCapacity(sizeStr string) error {
	if sizeStr == "" {
		return fmt.Errorf("storage size cannot be empty")
	}

	// Parse storage size and convert to bytes for validation
	size, unit, err := parseStorageSize(sizeStr)
	if err != nil {
		return err
	}

	// Convert to bytes
	bytes := convertToBytes(size, unit)

	// Minimum storage requirements
	minBytes := int64(1024 * 1024 * 1024) // 1GB minimum
	if bytes < minBytes {
		return fmt.Errorf("storage size too small (minimum 1Gi required)")
	}

	// Maximum reasonable storage for homelab
	maxBytes := int64(1024 * 1024 * 1024 * 1024) // 1TB maximum
	if bytes > maxBytes {
		return fmt.Errorf("storage size too large (maximum 1Ti for homelab)")
	}

	return nil
}

// ParseReplicaCount parses replica count string to int (exported for internal use)
func ParseReplicaCount(value string) (int, error) {
	if value == "" {
		return 0, fmt.Errorf("empty replica count")
	}

	count := 0
	if _, err := fmt.Sscanf(value, "%d", &count); err != nil {
		return 0, fmt.Errorf("invalid replica count format: %w", err)
	}

	return count, nil
}

// parseReplicaCount parses replica count string to int (internal)
func parseReplicaCount(value string) (int, error) {
	count, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil {
		return 0, fmt.Errorf("replica count must be a number")
	}
	return count, nil
}

// parseStorageSize parses storage size string (e.g., "10Gi" -> 10, "Gi")
func parseStorageSize(sizeStr string) (int64, string, error) {
	// Match number followed by optional unit
	re := regexp.MustCompile(`^(\d+)([KMGT]?i?)$`)
	matches := re.FindStringSubmatch(sizeStr)
	if len(matches) != 3 {
		return 0, "", fmt.Errorf("invalid storage size format")
	}

	size, err := strconv.ParseInt(matches[1], 10, 64)
	if err != nil {
		return 0, "", fmt.Errorf("invalid storage size number: %w", err)
	}

	unit := matches[2]
	if unit == "" {
		unit = "" // Assume bytes if no unit
	}

	return size, unit, nil
}

// convertToBytes converts size with unit to bytes
func convertToBytes(size int64, unit string) int64 {
	switch unit {
	case "Ki":
		return size * 1024
	case "Mi":
		return size * 1024 * 1024
	case "Gi":
		return size * 1024 * 1024 * 1024
	case "Ti":
		return size * 1024 * 1024 * 1024 * 1024
	case "K":
		return size * 1000
	case "M":
		return size * 1000 * 1000
	case "G":
		return size * 1000 * 1000 * 1000
	case "T":
		return size * 1000 * 1000 * 1000 * 1000
	default:
		return size // Assume bytes
	}
}