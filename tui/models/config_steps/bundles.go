package config_steps

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"ztc-tui/colors"
	"ztc-tui/components"
	"ztc-tui/utils"
)

// BundleModel handles workload bundle selection
type BundleModel struct {
	BaseStepModel
	
	// Bundle configuration
	availableBundles []utils.Bundle
	selectedBundles  []string
	bundleToggles    map[string]*components.ToggleField
	
	// UI state
	focusedField int
}

// NewBundleModel creates a new bundle selection model
func NewBundleModel() *BundleModel {
	return &BundleModel{
		BaseStepModel: BaseStepModel{
			Width:  80,
			Height: 24,
		},
		bundleToggles: make(map[string]*components.ToggleField),
	}
}

// Init initializes the bundle model
func (m BundleModel) Init() tea.Cmd {
	return nil
}

// InitWithConfig initializes the model with shared configuration
func (m *BundleModel) InitWithConfig(session *utils.Session, template *utils.ClusterConfig) tea.Cmd {
	m.session = session
	m.template = template
	
	// Load all available bundles
	m.availableBundles = utils.GetAvailableBundles()
	
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
	if template != nil {
		m.selectedBundles = template.Workloads.AutoDeployBundles
		for _, bundleID := range m.selectedBundles {
			if toggle, exists := m.bundleToggles[bundleID]; exists {
				toggle.SetValue(true)
			}
		}
	}
	
	return nil
}

// Update handles messages and user input
func (m *BundleModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	var cmds []tea.Cmd
	
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "tab", "down", "j":
			m.nextField()
		case "shift+tab", "up", "k":
			m.prevField()
		default:
			// Pass to focused component
			cmd = m.updateFocusedField(msg)
			if cmd != nil {
				cmds = append(cmds, cmd)
			}
		}
	
	case tea.MouseMsg:
		if msg.Type == tea.MouseLeft {
			// Handle mouse click to focus fields
			clickedFieldIndex := m.getFieldIndexFromY(msg.Y)
			if clickedFieldIndex >= 0 && clickedFieldIndex < len(m.availableBundles) {
				// Only change focus if clicking a different field
				if clickedFieldIndex != m.focusedField {
					m.setFocusIndex(clickedFieldIndex)
				}
			}
		}
	}
	
	return m, tea.Batch(cmds...)
}

// View renders the bundle selection interface
func (m BundleModel) View() string {
	var content strings.Builder
	
	// Step title
	title := lipgloss.NewStyle().
		Foreground(colors.ZtcOrange).
		Bold(true).
		Render("Workload Bundle Selection")
	content.WriteString(title + "\n\n")
	
	// Only show in advanced mode
	if m.session != nil && m.session.ConfigMode == utils.ConfigModeSimple {
		content.WriteString("Bundle selection is handled automatically in Simple mode.\n")
		content.WriteString("Recommended bundles will be pre-selected.\n\n")
		content.WriteString("Switch to Advanced mode (press 'M') for custom bundle selection.")
		return content.String()
	}
	
	content.WriteString("Choose applications to auto-deploy after cluster setup:\n\n")
	
	if len(m.availableBundles) == 0 {
		content.WriteString("No bundles available for this template.\n")
		return content.String()
	}
	
	// Render bundle toggles by category
	content.WriteString(m.renderBundlesByCategory())
	
	// Help text
	helpStyle := lipgloss.NewStyle().
		Foreground(colors.ZtcMutedGray).
		Italic(true)
	
	content.WriteString("\n\n")
	content.WriteString(helpStyle.Render("💡 Bundles can be deployed later using 'make deploy-bundle-<name>' commands.\n"))
	content.WriteString(helpStyle.Render("   Recommended bundles are pre-selected for common use cases."))
	
	return content.String()
}

// renderBundlesByCategory renders bundles grouped by category
func (m BundleModel) renderBundlesByCategory() string {
	var content strings.Builder
	
	// Group bundles by category (simplified categorization)
	categories := map[string][]utils.Bundle{
		"Essential":     {},
		"Monitoring":    {},
		"Productivity":  {},
		"Security":      {},
		"Development":   {},
	}
	
	for _, bundle := range m.availableBundles {
		// Simple categorization based on bundle name/description
		category := "Essential"
		name := strings.ToLower(bundle.Name)
		desc := strings.ToLower(bundle.Description)
		
		if strings.Contains(name, "monitoring") || strings.Contains(desc, "monitor") || 
		   strings.Contains(name, "grafana") || strings.Contains(name, "prometheus") {
			category = "Monitoring"
		} else if strings.Contains(name, "code") || strings.Contains(desc, "development") ||
		          strings.Contains(name, "git") {
			category = "Development"
		} else if strings.Contains(name, "vault") || strings.Contains(desc, "security") ||
		          strings.Contains(name, "auth") {
			category = "Security"
		} else if strings.Contains(name, "n8n") || strings.Contains(desc, "workflow") ||
		          strings.Contains(name, "productivity") {
			category = "Productivity"
		}
		
		categories[category] = append(categories[category], bundle)
	}
	
	// Render each category
	categoryOrder := []string{"Essential", "Monitoring", "Development", "Productivity", "Security"}
	
	for _, categoryName := range categoryOrder {
		bundles := categories[categoryName]
		if len(bundles) == 0 {
			continue
		}
		
		// Category header
		categoryStyle := lipgloss.NewStyle().
			Foreground(colors.ZtcLightGray).
			Bold(true).
			Underline(true)
		
		content.WriteString(categoryStyle.Render(fmt.Sprintf("📦 %s", categoryName)) + "\n")
		
		// Render bundles in category
		for _, bundle := range bundles {
			if toggle, exists := m.bundleToggles[bundle.ID]; exists {
				content.WriteString("  " + toggle.View() + "\n")
			}
		}
		content.WriteString("\n")
	}
	
	return content.String()
}

// Validate checks if bundle selection is valid
func (m BundleModel) Validate() error {
	// Bundle selection is always valid (optional)
	return nil
}

// ApplyToTemplate applies the bundle selection to the template
func (m BundleModel) ApplyToTemplate(template *utils.ClusterConfig) error {
	if template == nil {
		return nil
	}
	
	// Update selected bundles based on toggles
	var selectedBundles []string
	for _, bundle := range m.availableBundles {
		if toggle, exists := m.bundleToggles[bundle.ID]; exists && toggle.GetValue() {
			selectedBundles = append(selectedBundles, bundle.ID)
		}
	}
	
	template.Workloads.AutoDeployBundles = selectedBundles
	m.selectedBundles = selectedBundles
	
	return nil
}

// GetStepName returns the display name for this step
func (m BundleModel) GetStepName() string {
	return "Bundle Selection"
}

// ShouldShow returns true if this step should be shown in the given mode
func (m BundleModel) ShouldShow(mode utils.ConfigurationMode) bool {
	return mode == utils.ConfigModeAdvanced // Only show in advanced mode
}

// Focus management methods
func (m *BundleModel) nextField() {
	if len(m.availableBundles) > 0 && m.focusedField < len(m.availableBundles)-1 {
		m.focusedField++
		m.setFocus()
	}
}

func (m *BundleModel) prevField() {
	if m.focusedField > 0 {
		m.focusedField--
		m.setFocus()
	}
}

func (m *BundleModel) setFocus() {
	// Clear all focus first
	for _, toggle := range m.bundleToggles {
		toggle.Blur()
	}
	
	// Set focus on current field
	if m.focusedField < len(m.availableBundles) {
		bundleID := m.availableBundles[m.focusedField].ID
		if toggle, ok := m.bundleToggles[bundleID]; ok {
			toggle.Focus()
		}
	}
}

// setFocusIndex sets focus to a specific field index
func (m *BundleModel) setFocusIndex(index int) {
	m.focusedField = index
	m.setFocus()
}

// getFieldIndexFromY calculates which field was clicked based on Y coordinate
func (m *BundleModel) getFieldIndexFromY(y int) int {
	// Skip calculation in simple mode as it shows different content
	if m.session != nil && m.session.ConfigMode == utils.ConfigModeSimple {
		return -1
	}
	
	// Account for title and header (4 lines)
	// "Workload Bundle Selection" + "\n\n" + "Choose applications..." + "\n\n"
	headerOffset := 4
	
	// Each bundle takes approximately 4 lines (category header + toggle + \n)
	// This is a simplified calculation as bundles are grouped by categories
	bundleHeight := 4
	
	// Calculate which field was clicked
	adjustedY := y - headerOffset
	if adjustedY < 0 {
		return -1
	}
	
	fieldIndex := adjustedY / bundleHeight
	
	// Validate field index
	if fieldIndex >= len(m.availableBundles) {
		return -1
	}
	
	return fieldIndex
}

func (m *BundleModel) updateFocusedField(msg tea.Msg) tea.Cmd {
	if m.focusedField < len(m.availableBundles) {
		bundleID := m.availableBundles[m.focusedField].ID
		if toggle, ok := m.bundleToggles[bundleID]; ok {
			return toggle.Update(msg)
		}
	}
	return nil
}