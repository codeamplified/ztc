package utils

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/xeipuuv/gojsonschema"
	"gopkg.in/yaml.v3"
)

// Validation holds the schema and validation state
type Validation struct {
	schema      *gojsonschema.Schema
	schemaPath  string
	mutex       sync.RWMutex
	initialized bool
}

// ValidationError represents a schema validation error with context
type ValidationError struct {
	Field       string `json:"field"`
	Message     string `json:"message"`
	Value       string `json:"value,omitempty"`
	Suggestion  string `json:"suggestion,omitempty"`
	SchemaPath  string `json:"schema_path,omitempty"`
}

// ValidationResult contains validation results and errors
type ValidationResult struct {
	Valid  bool              `json:"valid"`
	Errors []ValidationError `json:"errors,omitempty"`
}

// Global validator instance
var validator *Validation
var validatorOnce sync.Once

// GetValidator returns the singleton validator instance
func GetValidator() *Validation {
	validatorOnce.Do(func() {
		validator = &Validation{
			schemaPath: filepath.Join(GetWorkspaceDir(), "schema", "cluster-schema.json"),
		}
	})
	return validator
}

// LoadSchema loads and parses the JSON schema file
func (v *Validation) LoadSchema() error {
	v.mutex.Lock()
	defer v.mutex.Unlock()

	if v.initialized {
		return nil // Already loaded
	}

	// Check if schema file exists
	if _, err := os.Stat(v.schemaPath); os.IsNotExist(err) {
		return fmt.Errorf("schema file not found: %s", v.schemaPath)
	}

	// Read schema file
	schemaBytes, err := os.ReadFile(v.schemaPath)
	if err != nil {
		return fmt.Errorf("failed to read schema file: %w", err)
	}

	// Create schema loader
	schemaLoader := gojsonschema.NewBytesLoader(schemaBytes)
	
	// Compile schema
	schema, err := gojsonschema.NewSchema(schemaLoader)
	if err != nil {
		return fmt.Errorf("failed to compile schema: %w", err)
	}

	v.schema = schema
	v.initialized = true
	return nil
}

// ValidateClusterConfig validates a ClusterConfig against the JSON schema
func (v *Validation) ValidateClusterConfig(config *ClusterConfig) (*ValidationResult, error) {
	// Ensure schema is loaded
	if err := v.LoadSchema(); err != nil {
		return nil, fmt.Errorf("failed to load schema: %w", err)
	}

	v.mutex.RLock()
	schema := v.schema
	v.mutex.RUnlock()

	// Convert ClusterConfig to JSON for validation
	configJSON, err := json.Marshal(config)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal config to JSON: %w", err)
	}

	// Create document loader
	documentLoader := gojsonschema.NewBytesLoader(configJSON)

	// Validate against schema
	result, err := schema.Validate(documentLoader)
	if err != nil {
		return nil, fmt.Errorf("validation failed: %w", err)
	}

	// Convert results
	validationResult := &ValidationResult{
		Valid:  result.Valid(),
		Errors: make([]ValidationError, 0),
	}

	// Convert schema errors to our format
	for _, err := range result.Errors() {
		validationErr := ValidationError{
			Field:      err.Field(),
			Message:    err.Description(),
			SchemaPath: err.Context().String(),
		}

		// Add helpful suggestions for common errors
		validationErr.Suggestion = generateSuggestion(err.Type(), err.Field(), err.Description())
		
		validationResult.Errors = append(validationResult.Errors, validationErr)
	}

	return validationResult, nil
}

// ValidateClusterConfigFromYAML validates a YAML string against the schema
func (v *Validation) ValidateClusterConfigFromYAML(yamlContent string) (*ValidationResult, error) {
	// Parse YAML into ClusterConfig
	var config ClusterConfig
	if err := yaml.Unmarshal([]byte(yamlContent), &config); err != nil {
		return &ValidationResult{
			Valid: false,
			Errors: []ValidationError{
				{
					Field:   "yaml",
					Message: fmt.Sprintf("Invalid YAML syntax: %v", err),
				},
			},
		}, nil
	}

	return v.ValidateClusterConfig(&config)
}

// ValidateClusterConfigFromFile validates a cluster.yaml file
func (v *Validation) ValidateClusterConfigFromFile(filePath string) (*ValidationResult, error) {
	// Read file
	content, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read file %s: %w", filePath, err)
	}

	return v.ValidateClusterConfigFromYAML(string(content))
}

// FormatValidationErrors converts validation errors to user-friendly messages
func (v *ValidationResult) FormatErrors() string {
	if v.Valid {
		return "✅ Configuration is valid"
	}

	var builder strings.Builder
	builder.WriteString("❌ Configuration validation failed:\n\n")

	for i, err := range v.Errors {
		builder.WriteString(fmt.Sprintf("%d. %s\n", i+1, formatSingleError(err)))
		if err.Suggestion != "" {
			builder.WriteString(fmt.Sprintf("   💡 Suggestion: %s\n", err.Suggestion))
		}
		builder.WriteString("\n")
	}

	return builder.String()
}

// formatSingleError formats a single validation error
func formatSingleError(err ValidationError) string {
	if err.Field != "" {
		return fmt.Sprintf("Field '%s': %s", err.Field, err.Message)
	}
	return err.Message
}

// generateSuggestion provides helpful suggestions for common validation errors
func generateSuggestion(errorType, field, description string) string {
	field = strings.ToLower(field)
	description = strings.ToLower(description)

	switch {
	case strings.Contains(field, "name") && strings.Contains(description, "pattern"):
		return "Use lowercase letters, numbers, and hyphens only (e.g., 'ztc-homelab')"
	case strings.Contains(field, "ip") && strings.Contains(description, "format"):
		return "Provide a valid IPv4 address (e.g., '192.168.50.10')"
	case strings.Contains(field, "subnet") && strings.Contains(description, "pattern"):
		return "Use CIDR notation (e.g., '192.168.50.0/24')"
	case strings.Contains(field, "domain") && strings.Contains(description, "pattern"):
		return "Use a valid domain format (e.g., 'homelab.lan')"
	case strings.Contains(field, "memory") && strings.Contains(description, "pattern"):
		return "Use memory units like '4Gi', '512Mi', or '2048Mi'"
	case strings.Contains(field, "cpu") && strings.Contains(description, "pattern"):
		return "Use CPU format like '2', '1.5', or '500m'"
	case strings.Contains(description, "required"):
		return "This field is mandatory and cannot be empty"
	case strings.Contains(description, "minimum"):
		return "Increase the value to meet the minimum requirement"
	case strings.Contains(description, "enum"):
		return "Use one of the allowed values specified in the schema"
	default:
		return "Check the JSON schema for valid values and format"
	}
}

// Convenience functions

// ValidateTemplate validates a template against the schema
func ValidateTemplate(config *ClusterConfig) error {
	validator := GetValidator()
	result, err := validator.ValidateClusterConfig(config)
	if err != nil {
		return fmt.Errorf("validation error: %w", err)
	}

	if !result.Valid {
		return fmt.Errorf("template validation failed:\n%s", result.FormatErrors())
	}

	return nil
}

// ValidateConfigFile validates a cluster.yaml file and returns user-friendly results
func ValidateConfigFile(filePath string) (*ValidationResult, error) {
	validator := GetValidator()
	return validator.ValidateClusterConfigFromFile(filePath)
}

// ValidateConfigYAML validates YAML content and returns user-friendly results
func ValidateConfigYAML(yamlContent string) (*ValidationResult, error) {
	validator := GetValidator()
	return validator.ValidateClusterConfigFromYAML(yamlContent)
}

// QuickValidate performs a quick validation and returns true/false
func QuickValidate(config *ClusterConfig) bool {
	validator := GetValidator()
	result, err := validator.ValidateClusterConfig(config)
	if err != nil {
		return false
	}
	return result.Valid
}