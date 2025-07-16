package models

import (
	"fmt"
	"net"
	"regexp"
	"strings"
	"errors"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"ztc-tui/components"
	"ztc-tui/utils"
)

// Mission constants from utils
const (
	MissionPioneer     = utils.MissionPioneer
	MissionHomesteader = utils.MissionHomesteader
)

type ConfigModel struct {
	Width   int
	Height  int
	session *utils.Session
	
	// Template-based configuration
	mission          utils.Mission
	template         *utils.ClusterConfig
	templateMetadata *utils.TemplateMetadata
	availableBundles []utils.Bundle
	selectedBundles  []string
	
	// Configuration state
	currentStep int
	steps       []string
	
	// Customization components (simplified)
	clusterNameInput   *components.InputField
	networkSubnetInput *components.InputField
	dnsDomainInput     *components.InputField
	bundleToggles      map[string]*components.ToggleField
	
	// UI state
	focusedField int
	fields       []string
	
	// Error state
	loadError string
	saveError string
}

type ConfigInitMsg struct {
	Session *utils.Session
	Mission utils.Mission
}

// Validation functions
func validateClusterName(value string) error {
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

func validateNetworkSubnet(value string) error {
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

func validateDNSDomain(value string) error {
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

// NewConfigModel creates a new template-based configuration model
func NewConfigModel() ConfigModel {
	return ConfigModel{
		Width:  80,
		Height: 24,
		steps: []string{
			"Template Preview",
			"Basic Customization",
			"Bundle Selection",
			"Final Review",
		},
		currentStep: 0,
		focusedField: 0,
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
		m.mission = msg.Mission
		
		// Load template for the selected mission
		template, err := utils.LoadClusterTemplate(m.mission)
		if err != nil {
			m.loadError = fmt.Sprintf("Failed to load template: %v", err)
			return m, nil
		}
		
		// Validate template
		if err := utils.ValidateTemplate(template); err != nil {
			m.loadError = fmt.Sprintf("Invalid template: %v", err)
			return m, nil
		}
		
		m.template = template
		
		// Load template metadata
		metadata, err := utils.GetTemplateMetadata(m.mission)
		if err != nil {
			m.loadError = fmt.Sprintf("Failed to load template metadata: %v", err)
			return m, nil
		}
		m.templateMetadata = metadata
		
		// Load available bundles for this mission
		m.availableBundles = utils.GetAvailableBundles(m.mission)
		
		// Initialize bundle toggles
		m.bundleToggles = make(map[string]*components.ToggleField)
		for _, bundle := range m.availableBundles {
			toggle := components.NewToggleField(
				fmt.Sprintf("%s - %s (%s)", bundle.Name, bundle.Description, bundle.Resources),
				bundle.Recommended,
			)
			m.bundleToggles[bundle.ID] = toggle
		}
		
		// Set pre-selected bundles from template
		m.selectedBundles = m.template.Workloads.AutoDeployBundles
		for _, bundleID := range m.selectedBundles {
			if toggle, exists := m.bundleToggles[bundleID]; exists {
				toggle.SetValue(true)
			}
		}
		
		// Initialize customization fields with template values
		m.clusterNameInput = components.NewInputField("Cluster Name", m.template.Cluster.Name, 40)
		m.clusterNameInput.SetValue(m.template.Cluster.Name)
		m.clusterNameInput.Validate = validateClusterName
		
		m.networkSubnetInput = components.NewInputField("Network Subnet", m.template.Network.Subnet, 40)
		m.networkSubnetInput.SetValue(m.template.Network.Subnet)
		m.networkSubnetInput.Validate = validateNetworkSubnet
		
		m.dnsDomainInput = components.NewInputField("DNS Domain", m.template.Network.DNS.Domain, 40)
		m.dnsDomainInput.SetValue(m.template.Network.DNS.Domain)
		m.dnsDomainInput.Validate = validateDNSDomain
		
		// Set focus
		m.setFocus()
		return m, nil
		
	case tea.KeyMsg:
		// Handle errors first
		if m.loadError != "" {
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
			if m.currentStep == len(m.steps)-1 {
				// Final step - save and continue
				if m.validateAllFields() {
					if err := m.saveConfiguration(); err != nil {
						m.saveError = fmt.Sprintf("Failed to save configuration: %v", err)
						return m, nil
					}
					m.saveError = ""
					return m, func() tea.Msg {
						return StateTransitionMsg{To: "usb"}
					}
				}
				return m, nil
			}
			// Move to next step
			if m.validateCurrentStep() {
				if m.currentStep < len(m.steps)-1 {
					m.currentStep++
					m.focusedField = 0
					m.setFocus()
				}
			}
		case "left", "h":
			if m.currentStep > 0 {
				m.currentStep--
				m.focusedField = 0
				m.setFocus()
			}
		case "right", "l":
			if m.currentStep < len(m.steps)-1 && m.validateCurrentStep() {
				m.currentStep++
				m.focusedField = 0
				m.setFocus()
			}
		case "tab", "down", "j":
			m.nextField()
		case "shift+tab", "up", "k":
			m.prevField()
		case "q", "ctrl+c":
			return m, func() tea.Msg {
				return StateTransitionMsg{To: "quit"}
			}
		case "esc":
			return m, func() tea.Msg {
				return StateTransitionMsg{To: "welcome"}
			}
		default:
			// Pass to focused component
			cmd = m.updateFocusedField(msg)
			if cmd != nil {
				cmds = append(cmds, cmd)
			}
		}
	}
	
	return m, tea.Batch(cmds...)
}

func (m ConfigModel) View() string {
	var content strings.Builder
	
	// Handle load errors
	if m.loadError != "" {
		title := lipgloss.NewStyle().
			Foreground(lipgloss.Color("#FF6600")).
			Bold(true).
			Render("Configuration Error")
		
		content.WriteString(title + "\n\n")
		content.WriteString(fmt.Sprintf("Error: %s\n\n", m.loadError))
		content.WriteString("Press Esc to go back or q to quit.\n")
		return content.String()
	}
	
	// Title with mission name
	missionName := "Unknown Mission"
	if m.templateMetadata != nil {
		missionName = m.templateMetadata.Name
	}
	
	title := lipgloss.NewStyle().
		Foreground(lipgloss.Color("#FFA500")).
		Bold(true).
		Render(fmt.Sprintf("Configure %s", missionName))
	
	content.WriteString(title + "\n\n")
	
	// Steps indicator
	stepsView := m.renderSteps()
	content.WriteString(stepsView + "\n\n")
	
	// Current step content
	stepContent := m.renderCurrentStep()
	content.WriteString(stepContent + "\n\n")
	
	// Navigation help
	helpText := m.getHelpText()
	help := lipgloss.NewStyle().
		Foreground(lipgloss.Color("#EAEAEA")).
		Render(helpText)
	
	content.WriteString(help)
	
	return content.String()
}

func (m ConfigModel) getHelpText() string {
	switch m.currentStep {
	case 0: // Template Preview
		return "Enter Next step • Esc Back • q Quit"
	case 1: // Basic Customization
		return "Tab/↑↓ Navigate fields • Type to edit • Enter Next step • ← Previous • Esc Back • q Quit"
	case 2: // Bundle Selection
		return "Tab/↑↓ Navigate bundles • Enter/Space Toggle • Enter Next step • ← Previous • Esc Back • q Quit"
	case 3: // Final Review
		return "Enter Save & Continue • ← Previous • Esc Back • q Quit"
	default:
		return "← → Navigate steps • Enter Continue • Esc Back • q Quit"
	}
}

func (m ConfigModel) renderSteps() string {
	var steps []string
	
	for i, step := range m.steps {
		style := lipgloss.NewStyle().Foreground(lipgloss.Color("#626262"))
		
		if i == m.currentStep {
			style = style.Foreground(lipgloss.Color("#00D4AA")).Bold(true)
		} else if i < m.currentStep {
			style = style.Foreground(lipgloss.Color("#04B575"))
		}
		
		prefix := "○"
		if i < m.currentStep {
			prefix = "●"
		} else if i == m.currentStep {
			prefix = "◐"
		}
		
		steps = append(steps, style.Render(fmt.Sprintf("%s %s", prefix, step)))
	}
	
	return strings.Join(steps, "  ")
}

func (m ConfigModel) renderCurrentStep() string {
	switch m.currentStep {
	case 0:
		return m.renderTemplatePreview()
	case 1:
		return m.renderBasicCustomization()
	case 2:
		return m.renderBundleSelection()
	case 3:
		return m.renderFinalReview()
	default:
		return "Unknown step"
	}
}

func (m ConfigModel) renderTemplatePreview() string {
	content := strings.Builder{}
	
	content.WriteString("Template Preview\n")
	content.WriteString("===============\n\n")
	
	if m.templateMetadata == nil {
		content.WriteString("Loading template...")
		return content.String()
	}
	
	// Mission overview
	content.WriteString(fmt.Sprintf("Mission: %s\n", m.templateMetadata.Name))
	content.WriteString(fmt.Sprintf("Description: %s\n\n", m.templateMetadata.Description))
	
	// Hardware requirements
	content.WriteString("Hardware Requirements:\n")
	content.WriteString(fmt.Sprintf("• Node Count: %s\n", m.templateMetadata.NodeCount))
	content.WriteString(fmt.Sprintf("• Resources: %s\n", m.templateMetadata.HardwareReq))
	content.WriteString(fmt.Sprintf("• Architecture: %s\n\n", m.templateMetadata.Architecture))
	
	// Storage strategy
	content.WriteString("Storage Types:\n")
	for _, storageType := range m.templateMetadata.StorageTypes {
		content.WriteString(fmt.Sprintf("• %s\n", storageType))
	}
	content.WriteString("\n")
	
	// Use cases and trade-offs
	content.WriteString("Perfect for:\n")
	for _, useCase := range m.templateMetadata.UseCases {
		content.WriteString(fmt.Sprintf("• %s\n", useCase))
	}
	content.WriteString("\n")
	
	if len(m.templateMetadata.TradeOffs) > 0 {
		content.WriteString("Trade-offs:\n")
		for _, tradeOff := range m.templateMetadata.TradeOffs {
			content.WriteString(fmt.Sprintf("• %s\n", tradeOff))
		}
		content.WriteString("\n")
	}
	
	content.WriteString("This template will be loaded and ready for customization.\n")
	
	return content.String()
}

func (m ConfigModel) renderBasicCustomization() string {
	content := strings.Builder{}
	
	content.WriteString("Basic Customization\n")
	content.WriteString("==================\n\n")
	content.WriteString("Customize the essential settings for your cluster:\n\n")
	
	if m.clusterNameInput != nil {
		content.WriteString(m.clusterNameInput.View())
		content.WriteString("\n\n")
	}
	
	if m.networkSubnetInput != nil {
		content.WriteString(m.networkSubnetInput.View())
		content.WriteString("\n\n")
	}
	
	if m.dnsDomainInput != nil {
		content.WriteString(m.dnsDomainInput.View())
		content.WriteString("\n\n")
	}
	
	content.WriteString("All other settings are optimized for your mission.\n")
	
	return content.String()
}

func (m ConfigModel) renderBundleSelection() string {
	content := strings.Builder{}
	
	content.WriteString("Workload Bundles\n")
	content.WriteString("===============\n\n")
	content.WriteString("Choose applications to auto-deploy after cluster setup:\n\n")
	
	if len(m.availableBundles) == 0 {
		content.WriteString("No bundles available for this mission.\n")
		return content.String()
	}
	
	// Render bundle toggles
	for _, bundle := range m.availableBundles {
		if toggle, exists := m.bundleToggles[bundle.ID]; exists {
			content.WriteString(toggle.View())
			content.WriteString("\n")
		}
	}
	
	content.WriteString("\nBundles can be deployed later using 'make deploy-bundle-<name>' commands.\n")
	
	return content.String()
}

func (m ConfigModel) renderFinalReview() string {
	content := strings.Builder{}
	
	content.WriteString("Final Review\n")
	content.WriteString("===========\n\n")
	
	if m.templateMetadata != nil {
		content.WriteString(fmt.Sprintf("Mission: %s\n", m.templateMetadata.Name))
	}
	
	if m.clusterNameInput != nil {
		content.WriteString(fmt.Sprintf("Cluster Name: %s\n", m.clusterNameInput.GetValue()))
	}
	
	if m.networkSubnetInput != nil {
		content.WriteString(fmt.Sprintf("Network: %s\n", m.networkSubnetInput.GetValue()))
	}
	
	if m.dnsDomainInput != nil {
		content.WriteString(fmt.Sprintf("DNS Domain: %s\n", m.dnsDomainInput.GetValue()))
	}
	
	// Show selected bundles
	var selectedBundles []string
	for _, bundle := range m.availableBundles {
		if toggle, exists := m.bundleToggles[bundle.ID]; exists && toggle.GetValue() {
			selectedBundles = append(selectedBundles, bundle.Name)
		}
	}
	
	if len(selectedBundles) > 0 {
		content.WriteString(fmt.Sprintf("Auto-Deploy Bundles: %s\n", strings.Join(selectedBundles, ", ")))
	} else {
		content.WriteString("Auto-Deploy Bundles: None\n")
	}
	
	content.WriteString("\n")
	
	// Show node information
	if m.template != nil {
		content.WriteString("Nodes:\n")
		for hostname, node := range m.template.Nodes.ClusterNodes {
			content.WriteString(fmt.Sprintf("• %s: %s (%s)\n", hostname, node.IP, node.Role))
		}
		for hostname, node := range m.template.Nodes.StorageNode {
			content.WriteString(fmt.Sprintf("• %s: %s (%s)\n", hostname, node.IP, node.Role))
		}
		content.WriteString("\n")
	}
	
	content.WriteString("Configuration ready!\n")
	
	// Show save error if present
	if m.saveError != "" {
		content.WriteString("\n")
		errorStyle := lipgloss.NewStyle().
			Foreground(lipgloss.Color("#FF6600")).
			Bold(true)
		content.WriteString(errorStyle.Render("⚠ " + m.saveError))
		content.WriteString("\n")
	}
	
	content.WriteString("Press Enter to continue to USB creation.\n")
	
	return content.String()
}

var stepFields = [][]string{
	{}, // Template Preview - no fields (read-only)
	{"clusterName", "networkSubnet", "dnsDomain"}, // Basic Customization
	{}, // Bundle Selection - dynamic fields based on available bundles
	{}, // Final Review - no fields (read-only)
}

// Helper methods for focus management
func (m *ConfigModel) setFocus() {
	// Clear all focus first
	if m.clusterNameInput != nil {
		m.clusterNameInput.Blur()
	}
	if m.networkSubnetInput != nil {
		m.networkSubnetInput.Blur()
	}
	if m.dnsDomainInput != nil {
		m.dnsDomainInput.Blur()
	}
	for _, toggle := range m.bundleToggles {
		toggle.Blur()
	}

	// Handle different steps
	switch m.currentStep {
	case 0, 3: // Template Preview and Final Review - no focus needed
		return
	case 1: // Basic Customization
		fields := stepFields[1]
		if m.focusedField >= len(fields) {
			return
		}
		fieldToFocus := fields[m.focusedField]
		switch fieldToFocus {
		case "clusterName":
			if m.clusterNameInput != nil {
				m.clusterNameInput.Focus()
			}
		case "networkSubnet":
			if m.networkSubnetInput != nil {
				m.networkSubnetInput.Focus()
			}
		case "dnsDomain":
			if m.dnsDomainInput != nil {
				m.dnsDomainInput.Focus()
			}
		}
	case 2: // Bundle Selection
		if m.focusedField < len(m.availableBundles) {
			bundleID := m.availableBundles[m.focusedField].ID
			if toggle, ok := m.bundleToggles[bundleID]; ok {
				toggle.Focus()
			}
		}
	}
}

func (m *ConfigModel) nextField() {
	switch m.currentStep {
	case 0, 3: // Template Preview and Final Review - no fields
		return
	case 1: // Basic Customization
		fields := stepFields[1]
		if m.focusedField < len(fields)-1 {
			m.focusedField++
			m.setFocus()
		}
	case 2: // Bundle Selection
		if m.focusedField < len(m.availableBundles)-1 {
			m.focusedField++
			m.setFocus()
		}
	}
}

func (m *ConfigModel) prevField() {
	if m.focusedField > 0 {
		m.focusedField--
		m.setFocus()
	}
}

func (m *ConfigModel) updateFocusedField(msg tea.Msg) tea.Cmd {
	switch m.currentStep {
	case 0, 3: // Template Preview and Final Review - no interaction
		return nil
	case 1: // Basic Customization
		fields := stepFields[1]
		if m.focusedField >= len(fields) {
			return nil
		}
		fieldToUpdate := fields[m.focusedField]
		switch fieldToUpdate {
		case "clusterName":
			if m.clusterNameInput != nil {
				return m.clusterNameInput.Update(msg)
			}
		case "networkSubnet":
			if m.networkSubnetInput != nil {
				return m.networkSubnetInput.Update(msg)
			}
		case "dnsDomain":
			if m.dnsDomainInput != nil {
				return m.dnsDomainInput.Update(msg)
			}
		}
	case 2: // Bundle Selection
		if m.focusedField < len(m.availableBundles) {
			bundleID := m.availableBundles[m.focusedField].ID
			if toggle, ok := m.bundleToggles[bundleID]; ok {
				return toggle.Update(msg)
			}
		}
	}
	return nil
}

func (m *ConfigModel) validateCurrentStep() bool {
	switch m.currentStep {
	case 0: // Template Preview - no validation needed
		return true
	case 1: // Basic Customization
		valid := true
		if m.clusterNameInput != nil && !m.clusterNameInput.ValidateInput() {
			valid = false
		}
		if m.networkSubnetInput != nil && !m.networkSubnetInput.ValidateInput() {
			valid = false
		}
		if m.dnsDomainInput != nil && !m.dnsDomainInput.ValidateInput() {
			valid = false
		}
		return valid
	case 2: // Bundle Selection - no validation needed (optional)
		return true
	case 3: // Final Review - no validation needed
		return true
	}
	return true
}

func (m *ConfigModel) validateAllFields() bool {
	valid := true
	
	if m.clusterNameInput != nil && !m.clusterNameInput.ValidateInput() {
		valid = false
	}
	if m.networkSubnetInput != nil && !m.networkSubnetInput.ValidateInput() {
		valid = false
	}
	if m.dnsDomainInput != nil && !m.dnsDomainInput.ValidateInput() {
		valid = false
	}
	
	return valid
}

func (m ConfigModel) saveConfiguration() error {
	if m.template == nil {
		return fmt.Errorf("no template loaded")
	}
	
	// Start with the loaded template
	config := *m.template
	
	// Apply customizations
	if m.clusterNameInput != nil {
		config.Cluster.Name = m.clusterNameInput.GetValue()
	}
	
	if m.networkSubnetInput != nil {
		config.Network.Subnet = m.networkSubnetInput.GetValue()
	}
	
	if m.dnsDomainInput != nil {
		config.Network.DNS.Domain = m.dnsDomainInput.GetValue()
	}
	
	// Update auto-deploy bundles based on selections
	var selectedBundles []string
	for _, bundle := range m.availableBundles {
		if toggle, exists := m.bundleToggles[bundle.ID]; exists && toggle.GetValue() {
			selectedBundles = append(selectedBundles, bundle.ID)
		}
	}
	config.Workloads.AutoDeployBundles = selectedBundles
	
	// Add generation metadata
	config.Cluster.Description = "Zero Touch Cluster - TUI Generated"
	if config.Cluster.Version == "" {
		config.Cluster.Version = "1.0.0"
	}
	
	// Validate configuration against schema before saving
	if validationResult, err := utils.GetValidator().ValidateClusterConfig(&config); err != nil {
		return fmt.Errorf("configuration validation failed: %w", err)
	} else if !validationResult.Valid {
		return fmt.Errorf("configuration is invalid:\n%s", validationResult.FormatErrors())
	}
	
	// Save to session
	if err := m.session.SaveClusterConfig(&config); err != nil {
		return err
	}
	
	// Mark step as completed
	return m.session.AddCompletedStep("configuration")
}