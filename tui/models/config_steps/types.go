package config_steps

import (
	tea "github.com/charmbracelet/bubbletea"
	"ztc-tui/utils"
)

// ConfigStepModel defines the interface that all configuration step models must implement
type ConfigStepModel interface {
	tea.Model
	
	// Initialize the model with shared configuration
	InitWithConfig(session *utils.Session, template *utils.ClusterConfig) tea.Cmd
	
	// Validate the current step's configuration
	Validate() error
	
	// Apply the configuration changes to the template
	ApplyToTemplate(template *utils.ClusterConfig) error
	
	// Get the step name for display
	GetStepName() string
	
	// Check if this step should be shown in the current mode
	ShouldShow(mode utils.ConfigurationMode) bool
}

// StepDefinition defines a complete step with its model and metadata
type StepDefinition struct {
	Model            ConfigStepModel
	SimpleName       string // Name shown in simple mode
	AdvancedName     string // Name shown in advanced mode  
	ShowInSimpleMode bool   // Whether to show this step in simple mode
}

// StepTransitionMsg is sent when transitioning between steps
type StepTransitionMsg struct {
	Direction string // "next", "previous", "specific"
	StepIndex int    // For "specific" direction
}

// StepValidationMsg is sent when validation state changes
type StepValidationMsg struct {
	IsValid bool
	Error   error
}

// ConfigurationCompleteMsg is sent when all configuration is complete
type ConfigurationCompleteMsg struct {
	Config *utils.ClusterConfig
}

// BaseStepModel provides common functionality for all step models
type BaseStepModel struct {
	Width   int
	Height  int
	session *utils.Session
	template *utils.ClusterConfig
	focused bool
}

// SetDimensions updates the model dimensions
func (m *BaseStepModel) SetDimensions(width, height int) {
	m.Width = width
	m.Height = height
}

// SetFocused sets the focus state
func (m *BaseStepModel) SetFocused(focused bool) {
	m.focused = focused
}

// IsFocused returns the focus state
func (m *BaseStepModel) IsFocused() bool {
	return m.focused
}

// GetSession returns the session
func (m *BaseStepModel) GetSession() *utils.Session {
	return m.session
}

// GetTemplate returns the template
func (m *BaseStepModel) GetTemplate() *utils.ClusterConfig {
	return m.template
}