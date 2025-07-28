package models

import (
	"fmt"
	"strings"

	"ztc-tui/colors"
	"ztc-tui/components"
	"ztc-tui/models/config_steps"
	"ztc-tui/utils"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Type aliases from config_steps package
type ConfigStepModel = config_steps.ConfigStepModel
type StepDefinition = config_steps.StepDefinition

type ConfigModel struct {
	Width    int
	Height   int
	session  *utils.Session
	viewport viewport.Model
	ready    bool

	// Template-based configuration
	templateID       string
	template         *utils.ClusterConfig
	templateMetadata *utils.TemplateMetadata

	// Step orchestration - single source of truth
	allSteps       []config_steps.StepDefinition
	visibleSteps   []*config_steps.StepDefinition
	currentStepIdx int

	// UI components
	modeIndicator *components.ModeIndicator
	stepIndicator *components.StepIndicator

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
		Width:          0, // Will be set by WindowSizeMsg
		Height:         0, // Will be set by WindowSizeMsg
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
	case tea.WindowSizeMsg:
		m.Width = msg.Width
		m.Height = msg.Height
		
		// Update viewport dimensions
		if !m.ready {
			// Initialize viewport if not ready (shouldn't happen with ConfigInitMsg fix, but keep as fallback)
			m.viewport = viewport.New(m.Width, m.Height-10) // Leave space for header and footer
			m.ready = true
		} else {
			// Resize existing viewport
			m.viewport.Width = m.Width
			m.viewport.Height = m.Height - 10
		}
		
		// Re-render content with new dimensions
		if m.ready && m.currentStepIdx < len(m.visibleSteps) {
			// Update width for all visible steps
			for i := range m.visibleSteps {
				if step, ok := m.visibleSteps[i].Model.(interface{ SetWidth(int) }); ok {
					step.SetWidth(m.Width)
				}
			}
			m.viewport.SetContent(m.renderCurrentStep())
			m.viewport.GotoTop()
		}

	case ConfigInitMsg:
		m.session = msg.Session
		m.templateID = msg.TemplateID

		// Initialize viewport immediately to avoid "Initializing..." state
		if !m.ready {
			// Use current dimensions if available, otherwise use defaults
			width := m.Width
			height := m.Height
			if width == 0 {
				width = 80  // Default width
			}
			if height == 0 {
				height = 24  // Default height
			}
			m.viewport = viewport.New(width, height-10) // Leave space for header and footer
			m.ready = true
		}

		// Initialize mode indicator
		m.modeIndicator = components.NewModeIndicator(m.session.ConfigMode)

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
		m.viewport.SetContent(m.renderCurrentStep())
		m.viewport.GotoTop()
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
			if m.currentStepIdx == len(m.visibleSteps)-1 {
				// Final step - save and continue
				if m.validateAllSteps() {
					if err := m.saveConfiguration(); err != nil {
						m.currentError = fmt.Errorf("Failed to save configuration: %w", err)
						return m, nil
					}
					
					// Update session state and save
					m.session.SetPhase("usb")
					m.session.AddCompletedStep("configuration")
					if err := m.session.Save(); err != nil {
						m.currentError = fmt.Errorf("Failed to save session state: %w", err)
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
				m.nextStep()
			}
		case "left", "h":
			m.prevStep()
		case "right", "l":
			if m.validateCurrentStepModel() {
				m.nextStep()
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
			// Delegate all other input to the current step
			if m.currentStepIdx < len(m.visibleSteps) {
				var updatedStep tea.Model
				updatedStep, cmd = m.visibleSteps[m.currentStepIdx].Model.Update(msg)
				m.visibleSteps[m.currentStepIdx].Model = updatedStep.(ConfigStepModel)
				if cmd != nil {
					cmds = append(cmds, cmd)
				}
				m.viewport.SetContent(m.renderCurrentStep())
				m.viewport.GotoTop()
			}
		}
	}

	m.viewport, cmd = m.viewport.Update(msg)
	cmds = append(cmds, cmd)

	return m, tea.Batch(cmds...)
}

func (m ConfigModel) View() string {
	if !m.ready {
		return "Initializing..."
	}
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

	// Viewport for scrollable content
	content.WriteString(m.viewport.View() + "\n\n")

	// Help text
	helpText := "↑/↓ Scroll • ←/→ Navigate • Enter Continue • M Switch Mode • Esc Back • q Quit"
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

// renderCurrentStep renders the current step (Pure rendering function)
func (m ConfigModel) renderCurrentStep() string {
	if m.currentStepIdx < len(m.visibleSteps) {
		currentStep := m.visibleSteps[m.currentStepIdx]
		return currentStep.Model.View()
	}
	
	return "No available steps for current configuration mode"
}

// nextStep navigates to the next step if possible
func (m *ConfigModel) nextStep() {
	if m.currentStepIdx < len(m.visibleSteps)-1 {
		m.currentStepIdx++
		if m.stepIndicator != nil {
			m.stepIndicator.SetCurrentStep(m.currentStepIdx)
		}
		m.viewport.SetContent(m.renderCurrentStep())
		m.viewport.GotoTop()
	}
}

// prevStep navigates to the previous step if possible
func (m *ConfigModel) prevStep() {
	if m.currentStepIdx > 0 {
		m.currentStepIdx--
		if m.stepIndicator != nil {
			m.stepIndicator.SetCurrentStep(m.currentStepIdx)
		}
		m.viewport.SetContent(m.renderCurrentStep())
		m.viewport.GotoTop()
	}
}

// initializeConfigSteps creates the step definitions and sets up visible steps
func (m *ConfigModel) initializeConfigSteps() {
	// Define all steps with their metadata - single source of truth
	m.allSteps = []StepDefinition{
		{
			Model:            config_steps.NewNetworkModel(),
			SimpleName:       "Network Setup",
			AdvancedName:     "Network Config", 
			ShowInSimpleMode: true,
		},
		{
			Model:            config_steps.NewSSHModel(),
			SimpleName:       "SSH Setup",
			AdvancedName:     "SSH Setup",
			ShowInSimpleMode: true,
		},
		{
			Model:            config_steps.NewStorageModel(),
			SimpleName:       "",
			AdvancedName:     "Storage Config",
			ShowInSimpleMode: false,
		},
		{
			Model:            config_steps.NewHAModel(),
			SimpleName:       "",
			AdvancedName:     "HA Config",
			ShowInSimpleMode: false,
		},
		{
			Model:            config_steps.NewBundleModel(),
			SimpleName:       "",
			AdvancedName:     "Bundle Selection",
			ShowInSimpleMode: false,
		},
		{
			Model:            config_steps.NewReviewModel(),
			SimpleName:       "Deploy Preview",
			AdvancedName:     "Final Review",
			ShowInSimpleMode: true,
		},
	}

	// Initialize all step models with session and template
	for i := range m.allSteps {
		m.allSteps[i].Model.InitWithConfig(m.session, m.template)
		// Set width if available
		if m.Width > 0 {
			if s, ok := m.allSteps[i].Model.(interface{ SetWidth(int) }); ok {
				s.SetWidth(m.Width)
			}
		}
	}

	// Build visible steps list based on current mode
	m.buildVisibleSteps()
	
	// Initialize step indicator with visible step names
	m.initializeStepIndicator()
	
	// Start at first step
	m.currentStepIdx = 0
}

// buildVisibleSteps creates the visibleSteps slice based on current configuration mode
func (m *ConfigModel) buildVisibleSteps() {
	m.visibleSteps = make([]*StepDefinition, 0)
	
	for i := range m.allSteps {
		step := &m.allSteps[i]
		if m.session.ConfigMode == utils.ConfigModeSimple {
			if step.ShowInSimpleMode {
				m.visibleSteps = append(m.visibleSteps, step)
			}
		} else {
			// Advanced mode shows all steps
			m.visibleSteps = append(m.visibleSteps, step)
		}
	}
}

// initializeStepIndicator creates the step indicator with names from visible steps
func (m *ConfigModel) initializeStepIndicator() {
	stepNames := make([]string, len(m.visibleSteps))
	
	for i, step := range m.visibleSteps {
		if m.session.ConfigMode == utils.ConfigModeSimple {
			stepNames[i] = step.SimpleName
		} else {
			stepNames[i] = step.AdvancedName
		}
	}
	
	m.stepIndicator = components.NewStepIndicator(stepNames, 0)
}

// validateCurrentStepModel validates the current step using the step's Validate method
func (m *ConfigModel) validateCurrentStepModel() bool {
	if m.currentStepIdx < len(m.visibleSteps) {
		currentStep := m.visibleSteps[m.currentStepIdx]
		if err := currentStep.Model.Validate(); err != nil {
			m.currentError = fmt.Errorf("Step validation failed: %w", err)
			return false
		}
		// Apply step changes to template
		if err := currentStep.Model.ApplyToTemplate(m.template); err != nil {
			m.currentError = fmt.Errorf("Failed to apply step configuration: %w", err)
			return false
		}
	}
	return true
}

// validateAllSteps validates all visible configuration steps
func (m *ConfigModel) validateAllSteps() bool {
	for i, stepDef := range m.visibleSteps {
		if err := stepDef.Model.Validate(); err != nil {
			m.currentError = fmt.Errorf("Step %d validation failed: %w", i+1, err)
			return false
		}
		// Apply step changes to template
		if err := stepDef.Model.ApplyToTemplate(m.template); err != nil {
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
	
	if m.session == nil {
		return fmt.Errorf("no session available")
	}
	
	// Save the cluster configuration to cluster.yaml
	if err := m.session.SaveClusterConfig(m.template); err != nil {
		return fmt.Errorf("failed to save cluster configuration: %w", err)
	}
	
	return nil
}






