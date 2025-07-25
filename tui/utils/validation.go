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
	Field         string `json:"field"`
	Message       string `json:"message"`
	Value         string `json:"value,omitempty"`
	Suggestion    string `json:"suggestion,omitempty"`
	SchemaPath    string `json:"schema_path,omitempty"`
	ErrorType     string `json:"error_type,omitempty"` // enum, pattern, required, etc.
	FieldPath     string `json:"field_path,omitempty"` // JSONPath to field
	SeverityLevel string `json:"severity,omitempty"`   // error, warning, info
}

// ValidationResult contains validation results and errors
type ValidationResult struct {
	Valid    bool              `json:"valid"`
	Errors   []ValidationError `json:"errors,omitempty"`
	Warnings []ValidationError `json:"warnings,omitempty"`
	Summary  ValidationSummary `json:"summary"`
}

// ValidationSummary provides overview of validation results
type ValidationSummary struct {
	TotalErrors   int            `json:"total_errors"`
	TotalWarnings int            `json:"total_warnings"`
	FieldsChecked int            `json:"fields_checked"`
	Categories    map[string]int `json:"category_counts"`
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

// ValidateSchemaFile validates that the schema file itself is valid JSON
func (v *Validation) ValidateSchemaFile() error {
	// Check if schema file exists
	if _, err := os.Stat(v.schemaPath); os.IsNotExist(err) {
		return fmt.Errorf("❌ Schema file not found: %s", v.schemaPath)
	}

	// Read schema file
	schemaBytes, err := os.ReadFile(v.schemaPath)
	if err != nil {
		return fmt.Errorf("❌ Failed to read schema file: %w", err)
	}

	// Test JSON parsing
	var schemaObj interface{}
	if err := json.Unmarshal(schemaBytes, &schemaObj); err != nil {
		return fmt.Errorf("❌ Invalid JSON in schema file:\n%s\n\n💡 Suggestion: Check for trailing commas, missing quotes, or syntax errors in %s", err.Error(), v.schemaPath)
	}

	return nil
}

// LoadSchema loads and parses the JSON schema file
func (v *Validation) LoadSchema() error {
	v.mutex.Lock()
	defer v.mutex.Unlock()

	if v.initialized {
		return nil // Already loaded
	}

	// First validate schema file integrity
	if err := v.ValidateSchemaFile(); err != nil {
		return err
	}

	// Read schema file
	schemaBytes, err := os.ReadFile(v.schemaPath)
	if err != nil {
		return fmt.Errorf("❌ Failed to read schema file: %w", err)
	}

	// Create schema loader
	schemaLoader := gojsonschema.NewBytesLoader(schemaBytes)

	// Compile schema
	schema, err := gojsonschema.NewSchema(schemaLoader)
	if err != nil {
		return fmt.Errorf("❌ Failed to compile schema: %w\n\n💡 Suggestion: The JSON schema has structural issues. Check the schema syntax in %s", err, v.schemaPath)
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

	// Convert results with enhanced error categorization
	validationResult := &ValidationResult{
		Valid:    result.Valid(),
		Errors:   make([]ValidationError, 0),
		Warnings: make([]ValidationError, 0),
		Summary: ValidationSummary{
			Categories: make(map[string]int),
		},
	}

	// Convert schema errors to our format
	for _, err := range result.Errors() {
		validationErr := ValidationError{
			Field:      err.Field(),
			Message:    err.Description(),
			SchemaPath: err.Context().String(),
			ErrorType:  err.Type(),
			FieldPath:  err.Context().String(),
		}

		// Categorize error severity
		severity := categorizeErrorSeverity(err.Type(), err.Field())
		validationErr.SeverityLevel = severity

		// Add helpful suggestions for common errors
		validationErr.Suggestion = generateSuggestion(err.Type(), err.Field(), err.Description())

		// Add to appropriate category
		if severity == "warning" {
			validationResult.Warnings = append(validationResult.Warnings, validationErr)
		} else {
			validationResult.Errors = append(validationResult.Errors, validationErr)
		}

		// Update category counts
		category := getErrorCategory(err.Type(), err.Field())
		validationResult.Summary.Categories[category]++
	}

	// Update summary counts
	validationResult.Summary.TotalErrors = len(validationResult.Errors)
	validationResult.Summary.TotalWarnings = len(validationResult.Warnings)
	validationResult.Summary.FieldsChecked = countConfigFields(config)

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

// FormatWarnings converts validation warnings to user-friendly messages
func (v *ValidationResult) FormatWarnings() string {
	if len(v.Warnings) == 0 {
		return ""
	}

	var builder strings.Builder
	builder.WriteString("⚠️ Configuration warnings:\n\n")

	for i, warning := range v.Warnings {
		builder.WriteString(fmt.Sprintf("%d. %s\n", i+1, formatSingleError(warning)))
		if warning.Suggestion != "" {
			builder.WriteString(fmt.Sprintf("   💡 Suggestion: %s\n", warning.Suggestion))
		}
		builder.WriteString("\n")
	}

	return builder.String()
}

// FormatSummary provides a quick overview of validation results
func (v *ValidationResult) FormatSummary() string {
	var builder strings.Builder

	if v.Valid {
		builder.WriteString("✅ Configuration is valid")
	} else {
		builder.WriteString(fmt.Sprintf("❌ %d validation errors", v.Summary.TotalErrors))
	}

	if v.Summary.TotalWarnings > 0 {
		builder.WriteString(fmt.Sprintf(" ⚠️ %d warnings", v.Summary.TotalWarnings))
	}

	if len(v.Summary.Categories) > 0 {
		builder.WriteString(" (")
		categories := make([]string, 0, len(v.Summary.Categories))
		for category, count := range v.Summary.Categories {
			categories = append(categories, fmt.Sprintf("%s: %d", category, count))
		}
		builder.WriteString(strings.Join(categories, ", "))
		builder.WriteString(")")
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

// categorizeErrorSeverity determines if an error should be treated as an error or warning
func categorizeErrorSeverity(errorType, field string) string {
	field = strings.ToLower(field)
	errorType = strings.ToLower(errorType)

	// Warnings: optional fields or non-critical issues
	switch {
	case strings.Contains(field, "description"):
		return "warning"
	case strings.Contains(field, "optional"):
		return "warning"
	case errorType == "additional_property_not_allowed" && strings.Contains(field, "metadata"):
		return "warning"
	default:
		return "error"
	}
}

// getErrorCategory categorizes errors for summary reporting
func getErrorCategory(errorType, field string) string {
	field = strings.ToLower(field)

	switch {
	case strings.Contains(field, "network") || strings.Contains(field, "ip") || strings.Contains(field, "subnet"):
		return "network"
	case strings.Contains(field, "storage") || strings.Contains(field, "volume"):
		return "storage"
	case strings.Contains(field, "node") || strings.Contains(field, "cluster_nodes"):
		return "nodes"
	case strings.Contains(field, "component"):
		return "components"
	case strings.Contains(field, "ssh") || strings.Contains(field, "auth"):
		return "auth"
	case strings.Contains(field, "ha") || strings.Contains(field, "high_availability"):
		return "ha"
	default:
		return "general"
	}
}

// countConfigFields estimates the number of fields being validated
func countConfigFields(config *ClusterConfig) int {
	// Basic estimation - could be made more sophisticated
	count := 10 // base fields (name, description, etc.)

	// Count nodes
	count += len(config.Nodes.ClusterNodes) * 3 // ip, role, resources

	// Count storage providers
	if config.Storage.LocalPath.Enabled {
		count += 2
	}
	if config.Storage.Longhorn.Enabled {
		count += 5
	}
	if config.Storage.NFS.Enabled {
		count += 4
	}

	// Count components
	if config.Components.ArgoCD.Enabled {
		count += 2
	}
	if config.Components.Monitoring.Enabled {
		count += 3
	}
	if config.Components.Gitea.Enabled {
		count += 2
	}
	if config.Components.MinIO.Enabled {
		count += 4
	}

	return count
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

// ValidateSchemaHealth performs comprehensive schema health checks
func ValidateSchemaHealth() (*ValidationResult, error) {
	validator := GetValidator()

	// Create a validation result for schema health checks
	result := &ValidationResult{
		Valid:    true,
		Errors:   make([]ValidationError, 0),
		Warnings: make([]ValidationError, 0),
		Summary: ValidationSummary{
			Categories: make(map[string]int),
		},
	}

	// Check 1: Schema file existence and readability
	if err := validator.ValidateSchemaFile(); err != nil {
		result.Valid = false
		result.Errors = append(result.Errors, ValidationError{
			Field:         "schema_file",
			Message:       err.Error(),
			ErrorType:     "file_error",
			SeverityLevel: "error",
			Suggestion:    "Ensure the cluster-schema.json file exists and is readable in the schema/ directory",
		})
		result.Summary.Categories["schema_file"]++
	}

	// Check 2: Schema compilation
	if err := validator.LoadSchema(); err != nil {
		result.Valid = false
		result.Errors = append(result.Errors, ValidationError{
			Field:         "schema_compilation",
			Message:       err.Error(),
			ErrorType:     "schema_error",
			SeverityLevel: "error",
			Suggestion:    "Check JSON syntax in schema/cluster-schema.json for missing commas, brackets, or quotes",
		})
		result.Summary.Categories["schema_compilation"]++
	}

	// Check 3: Template validation (only if schema loads successfully)
	if result.Valid {
		templates, err := LoadAvailableTemplates()
		if err != nil {
			result.Warnings = append(result.Warnings, ValidationError{
				Field:         "templates",
				Message:       fmt.Sprintf("Failed to load templates: %v", err),
				ErrorType:     "template_loading",
				SeverityLevel: "warning",
				Suggestion:    "Ensure templates directory exists and contains valid cluster-*.yaml files",
			})
			result.Summary.Categories["templates"]++
		} else {
			// Validate each template against the schema
			for _, templateInfo := range templates {
				config, err := LoadClusterTemplate(templateInfo.ID)
				if err != nil {
					result.Warnings = append(result.Warnings, ValidationError{
						Field:         fmt.Sprintf("template_%s", templateInfo.ID),
						Message:       fmt.Sprintf("Template %s failed to load: %v", templateInfo.Name, err),
						ErrorType:     "template_parsing",
						SeverityLevel: "warning",
						Suggestion:    fmt.Sprintf("Check YAML syntax in %s", templateInfo.FilePath),
					})
					result.Summary.Categories["templates"]++
					continue
				}

				// Validate template against schema
				if templateResult, err := validator.ValidateClusterConfig(config); err != nil {
					result.Warnings = append(result.Warnings, ValidationError{
						Field:         fmt.Sprintf("template_%s_validation", templateInfo.ID),
						Message:       fmt.Sprintf("Template %s validation error: %v", templateInfo.Name, err),
						ErrorType:     "template_validation",
						SeverityLevel: "warning",
						Suggestion:    "Fix template to match the current schema requirements",
					})
					result.Summary.Categories["templates"]++
				} else if !templateResult.Valid {
					// Template has validation errors
					result.Warnings = append(result.Warnings, ValidationError{
						Field:         fmt.Sprintf("template_%s_schema", templateInfo.ID),
						Message:       fmt.Sprintf("Template %s does not match schema (%d errors)", templateInfo.Name, len(templateResult.Errors)),
						ErrorType:     "template_schema",
						SeverityLevel: "warning",
						Suggestion:    "Update template to match current schema or fix validation errors",
					})
					result.Summary.Categories["templates"]++
				}
			}
		}
	}

	// Update summary counts
	result.Summary.TotalErrors = len(result.Errors)
	result.Summary.TotalWarnings = len(result.Warnings)
	result.Summary.FieldsChecked = 3 // schema file, compilation, templates

	return result, nil
}
