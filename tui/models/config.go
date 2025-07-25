package models

import (
	"fmt"
	"strings"

	"ztc-tui/colors"
	"ztc-tui/components"
	"ztc-tui/models/config_steps"
	"ztc-tui/utils"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ConfigStepModel interface alias from config_steps package
type ConfigStepModel = config_steps.ConfigStepModel

type ConfigModel struct {
	Width   int
	Height  int
	session *utils.Session

	// Template-based configuration
	templateID       string
	template         *utils.ClusterConfig
	templateMetadata *utils.TemplateMetadata

	// Phase 3: Step orchestration
	configSteps    []ConfigStepModel
	currentStepIdx int

	// Configuration state (legacy - needed for step indicators)
	currentStep   int
	steps         []string
	modeIndicator *components.ModeIndicator
	stepIndicator *components.StepIndicator

	// UI state (legacy - will be removed)
	focusedField int
	fields       []string

	// Error state
	currentError   error
	schemaWarnings string
}

type ConfigInitMsg struct {
	Session    *utils.Session
	TemplateID string
}

// NewConfigModel creates a new configuration model
func NewConfigModel() ConfigModel {
	return ConfigModel{
		Width:  80,
		Height: 24,
		configSteps: []ConfigStepModel{},
		currentStepIdx: 0,
	}
}

func (m ConfigModel) Init() tea.Cmd {
	return nil
}

func (m ConfigModel) Update(msg tea.Msg) (ConfigModel, tea.Cmd) {
	var cmd tea.Cmd
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case ConfigInitMsg:
		m.session = msg.Session
		m.templateID = msg.TemplateID

		// Initialize mode indicator
		m.modeIndicator = components.NewModeIndicator(m.session.ConfigMode)

		// Set up different step flows based on configuration mode
		if m.session.ConfigMode == utils.ConfigModeSimple {
			m.steps = []string{
				"Network Setup",
				"SSH Setup", 
				"Deploy Preview",
			}
		} else {
			m.steps = []string{
				"Network Config",
				"SSH Setup",
				"Storage Config",
				"HA Config",
				"Bundle Selection",
				"Final Review",
			}
		}

		// Initialize step indicator
		m.stepIndicator = components.NewStepIndicator(m.steps, m.currentStep)

		// Load template
		template, err := utils.LoadClusterTemplate(m.templateID)
		if err != nil {
			m.currentError = fmt.Errorf("Failed to load template: %w", err)
			return m, nil
		}
		m.template = template

		// Create metadata
		metadata := &utils.TemplateMetadata{
			Name:        template.Cluster.Name,
			Description: template.Cluster.Description,
			NodeCount:   fmt.Sprintf("%d nodes", len(template.Nodes.ClusterNodes)),
		}
		m.templateMetadata = metadata

		// Phase 3: Initialize configuration steps
		m.initializeConfigSteps()
		return m, nil

	case tea.KeyMsg:
		// Handle errors first
		if m.currentError != nil {
			switch msg.String() {
			case "esc":
				return m, func() tea.Msg {
					return StateTransitionMsg{To: "welcome"}
				}
			case "q", "ctrl+c":
				return m, func() tea.Msg {
					return StateTransitionMsg{To: "quit"}
				}
			}
			return m, nil
		}

		switch msg.String() {
		case "enter":
			if m.currentStepIdx == len(m.configSteps)-1 {
				// Final step - save and continue
				if m.validateAllSteps() {
					if err := m.saveConfiguration(); err != nil {
						m.currentError = fmt.Errorf("Failed to save configuration: %w", err)
						return m, nil
					}
					m.currentError = nil
					return m, func() tea.Msg {
						return StateTransitionMsg{To: "usb"}
					}
				}
				return m, nil
			}
			// Move to next step
			if m.validateCurrentStepModel() {
				if m.currentStepIdx < len(m.configSteps)-1 {
					m.currentStepIdx++
					if m.stepIndicator != nil {
						m.stepIndicator.SetCurrentStep(m.currentStepIdx)
					}
				}
			}
		case "left", "h":
			if m.currentStepIdx > 0 {
				m.currentStepIdx--
				if m.stepIndicator != nil {
					m.stepIndicator.SetCurrentStep(m.currentStepIdx)
				}
			}
		case "right", "l":
			if m.currentStepIdx < len(m.configSteps)-1 && m.validateCurrentStepModel() {
				m.currentStepIdx++
				if m.stepIndicator != nil {
					m.stepIndicator.SetCurrentStep(m.currentStepIdx)
				}
			}
		case "q", "ctrl+c":
			return m, func() tea.Msg {
				return StateTransitionMsg{To: "quit"}
			}
		case "esc":
			return m, func() tea.Msg {
				return StateTransitionMsg{To: "welcome"}
			}
		default:
			// Phase 3: Delegate all other input to the current step
			if m.currentStepIdx < len(m.configSteps) {
				var updatedStep tea.Model
				updatedStep, cmd = m.configSteps[m.currentStepIdx].Update(msg)
				m.configSteps[m.currentStepIdx] = updatedStep.(ConfigStepModel)
				if cmd != nil {
					cmds = append(cmds, cmd)
				}
			}
		}
	}

	return m, tea.Batch(cmds...)
}

func (m ConfigModel) View() string {
	var content strings.Builder

	// Handle errors
	if m.currentError != nil {
		title := lipgloss.NewStyle().
			Foreground(colors.ZtcOrange).
			Bold(true).
			Render("Configuration Error")

		content.WriteString(title + "\n\n")
		content.WriteString(fmt.Sprintf("Error: %s\n\n", m.currentError.Error()))
		content.WriteString("Press Esc to go back or q to quit.\n")
		return content.String()
	}

	// Enhanced title
	missionName := "Unknown Mission"
	if m.templateMetadata != nil {
		missionName = m.templateMetadata.Name
	}

	titleStyle := lipgloss.NewStyle().
		Foreground(colors.ZtcOrange).
		Bold(true).
		Border(lipgloss.NormalBorder(), false, false, true, false).
		BorderForeground(colors.ZtcLightGray).
		PaddingBottom(1).
		MarginBottom(1)

	title := titleStyle.Render(fmt.Sprintf("🏗️  Configure %s", missionName))
	content.WriteString(title + "\n")

	// Mode indicator
	if m.modeIndicator != nil {
		content.WriteString(m.modeIndicator.Compact() + "\n\n")
	}

	// Steps indicator
	if m.stepIndicator != nil {
		content.WriteString(m.stepIndicator.View() + "\n\n")
	}

	// Phase 3: Current step content via delegation
	stepContent := m.renderCurrentStep()
	content.WriteString(stepContent + "\n\n")

	// Help text
	helpText := "← → Navigate • Enter Continue • M Switch Mode • Esc Back • q Quit"
	helpStyle := lipgloss.NewStyle().
		Foreground(colors.ZtcMutedGray).
		Border(lipgloss.NormalBorder(), true, false, false, false).
		BorderForeground(colors.ZtcLightGray).
		PaddingTop(1).
		MarginTop(1)

	help := helpStyle.Render(fmt.Sprintf("⌨️  %s", helpText))
	content.WriteString(help)

	return content.String()
}

// Phase 3: Delegate rendering to current step model
func (m ConfigModel) renderCurrentStep() string {
	if m.currentStepIdx < len(m.configSteps) {
		currentStep := m.configSteps[m.currentStepIdx]
		
		// Only show steps that should be visible in current mode
		if m.session != nil && currentStep.ShouldShow(m.session.ConfigMode) {
			return currentStep.View()
		}
		
		// Skip steps that shouldn't be shown and move to next
		if m.currentStepIdx < len(m.configSteps)-1 {
			m.currentStepIdx++
			return m.renderCurrentStep()
		}
	}
	
	return "No available steps for current configuration mode"
}

// Phase 3: initializeConfigSteps creates and initializes all configuration step models
func (m *ConfigModel) initializeConfigSteps() {
	m.configSteps = []ConfigStepModel{
		config_steps.NewNetworkModel(),
		config_steps.NewSSHModel(),
		config_steps.NewStorageModel(),
		config_steps.NewHAModel(),
		config_steps.NewBundleModel(),
		config_steps.NewReviewModel(),
	}

	// Initialize each step with session and template
	for _, step := range m.configSteps {
		step.InitWithConfig(m.session, m.template)
	}

	// Set current step to 0
	m.currentStepIdx = 0
}

// Phase 3: validateCurrentStepModel validates the current step using the step's Validate method
func (m *ConfigModel) validateCurrentStepModel() bool {
	if m.currentStepIdx < len(m.configSteps) {
		if err := m.configSteps[m.currentStepIdx].Validate(); err != nil {
			m.currentError = fmt.Errorf("Step validation failed: %w", err)
			return false
		}
		// Apply step changes to template
		if err := m.configSteps[m.currentStepIdx].ApplyToTemplate(m.template); err != nil {
			m.currentError = fmt.Errorf("Failed to apply step configuration: %w", err)
			return false
		}
	}
	return true
}

// Phase 3: validateAllSteps validates all configuration steps
func (m *ConfigModel) validateAllSteps() bool {
	for i, step := range m.configSteps {
		if err := step.Validate(); err != nil {
			m.currentError = fmt.Errorf("Step %d validation failed: %w", i+1, err)
			return false
		}
		// Apply step changes to template
		if err := step.ApplyToTemplate(m.template); err != nil {
			m.currentError = fmt.Errorf("Failed to apply step %d configuration: %w", i+1, err)
			return false
		}
	}
	return true
}

// saveConfiguration saves the final configuration
func (m *ConfigModel) saveConfiguration() error {
	if m.template == nil {
		return fmt.Errorf("no template to save")
	}
	
	// Here you would implement the actual save logic
	// For now, just return success
	return nil
}