package config_steps

import (
	"fmt"
	"strconv"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"ztc-tui/colors"
	"ztc-tui/components"
	"ztc-tui/utils"
	"ztc-tui/validation"
)

// HAModel handles High Availability configuration
type HAModel struct {
	BaseStepModel
	
	// HA configuration components
	haEnabledToggle          *components.ToggleField
	haVirtualIPInput         *components.InputField
	haLoadBalancerTypeSelect *components.SelectField
	haLoadBalancerPortInput  *components.InputField
	haEtcdSnapshotCountInput *components.InputField
	haEtcdHeartbeatInput     *components.InputField
	
	// UI state
	focusedField int
	fields       []string
}

// NewHAModel creates a new HA configuration model
func NewHAModel() *HAModel {
	return &HAModel{
		BaseStepModel: BaseStepModel{
			Width:  80,
			Height: 24,
		},
		fields: []string{
			"haEnabled",
			"haVirtualIP",
			"haLoadBalancerType",
			"haLoadBalancerPort",
			"haEtcdSnapshotCount",
			"haEtcdHeartbeat",
		},
	}
}

// Init initializes the HA model
func (m HAModel) Init() tea.Cmd {
	return nil
}

// InitWithConfig initializes the model with shared configuration
func (m *HAModel) InitWithConfig(session *utils.Session, template *utils.ClusterConfig) tea.Cmd {
	m.session = session
	m.template = template
	
	if template == nil {
		return nil
	}
	
	// Initialize HA configuration fields
	haEnabled := template.Cluster.HAConfig != nil && template.Cluster.HAConfig.Enabled
	m.haEnabledToggle = components.NewToggleField("Enable High Availability", haEnabled)
	
	// Virtual IP
	virtualIP := ""
	if template.Cluster.HAConfig != nil {
		virtualIP = template.Cluster.HAConfig.VirtualIP
	}
	m.haVirtualIPInput = components.NewInputField("Virtual IP Address", "192.168.50.100", 40)
	m.haVirtualIPInput.SetValue(virtualIP)
	m.haVirtualIPInput.Validate = validation.ValidateVirtualIP
	
	// Load balancer configuration
	loadBalancerTypes := []string{"kube-vip", "haproxy", "nginx"}
	m.haLoadBalancerTypeSelect = components.NewSelectField("Load Balancer Type", loadBalancerTypes, 20)
	if template.Cluster.HAConfig != nil && template.Cluster.HAConfig.LoadBalancer != nil {
		m.haLoadBalancerTypeSelect.SetValue(template.Cluster.HAConfig.LoadBalancer.Type)
	}
	
	loadBalancerPort := ""
	if template.Cluster.HAConfig != nil && template.Cluster.HAConfig.LoadBalancer != nil && template.Cluster.HAConfig.LoadBalancer.Port > 0 {
		loadBalancerPort = strconv.Itoa(template.Cluster.HAConfig.LoadBalancer.Port)
	}
	m.haLoadBalancerPortInput = components.NewInputField("Load Balancer Port (optional)", "6443", 20)
	m.haLoadBalancerPortInput.SetValue(loadBalancerPort)
	m.haLoadBalancerPortInput.Validate = validation.ValidateLoadBalancerPort
	
	// Etcd configuration
	etcdSnapshotCount := ""
	if template.Cluster.HAConfig != nil && template.Cluster.HAConfig.EtcdConfig != nil && template.Cluster.HAConfig.EtcdConfig.SnapshotCount > 0 {
		etcdSnapshotCount = strconv.Itoa(template.Cluster.HAConfig.EtcdConfig.SnapshotCount)
	}
	m.haEtcdSnapshotCountInput = components.NewInputField("Etcd Snapshot Count (optional)", "10000", 20)
	m.haEtcdSnapshotCountInput.SetValue(etcdSnapshotCount)
	m.haEtcdSnapshotCountInput.Validate = validation.ValidateEtcdSnapshotCount
	
	heartbeat := ""
	if template.Cluster.HAConfig != nil && template.Cluster.HAConfig.EtcdConfig != nil {
		heartbeat = template.Cluster.HAConfig.EtcdConfig.HeartbeatInterval
	}
	m.haEtcdHeartbeatInput = components.NewInputField("Etcd Heartbeat Interval (optional)", "100ms", 20)
	m.haEtcdHeartbeatInput.SetValue(heartbeat)
	m.haEtcdHeartbeatInput.Validate = validation.ValidateEtcdHeartbeatInterval
	
	// Set initial focus
	m.setFocus()
	
	return nil
}

// Update handles messages and user input
func (m *HAModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
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
			if clickedFieldIndex >= 0 && clickedFieldIndex < len(m.fields) {
				// Only change focus if clicking a different field
				if clickedFieldIndex != m.focusedField {
					m.setFocusIndex(clickedFieldIndex)
				}
			}
		}
	}
	
	return m, tea.Batch(cmds...)
}

// View renders the HA configuration interface
func (m HAModel) View() string {
	var content strings.Builder
	
	// Step title
	title := lipgloss.NewStyle().
		Foreground(colors.ZtcOrange).
		Bold(true).
		Render("High Availability Configuration")
	content.WriteString(title + "\n\n")
	
	// Only show in advanced mode
	if m.session != nil && m.session.ConfigMode == utils.ConfigModeSimple {
		content.WriteString("High Availability is not available in Simple mode.\n")
		content.WriteString("Switch to Advanced mode (press 'M') for HA configuration.")
		return content.String()
	}
	
	content.WriteString("Configure high availability for your cluster:\n\n")
	
	// HA enabled toggle
	if m.haEnabledToggle != nil {
		content.WriteString(m.haEnabledToggle.View() + "\n\n")
		
		// Show HA configuration only if enabled
		if m.haEnabledToggle.GetValue() {
			content.WriteString(m.renderHAConfiguration())
		} else {
			helpStyle := lipgloss.NewStyle().
				Foreground(colors.ZtcMutedGray).
				Italic(true)
			content.WriteString(helpStyle.Render("💡 Enable HA to configure virtual IP and load balancing settings."))
		}
	}
	
	return content.String()
}

// renderHAConfiguration renders the HA configuration fields
func (m HAModel) renderHAConfiguration() string {
	var content strings.Builder
	
	// Virtual IP section
	sectionStyle := lipgloss.NewStyle().
		Foreground(colors.ZtcLightGray).
		Bold(true)
	
	content.WriteString(sectionStyle.Render("🌐 Virtual IP Configuration") + "\n")
	if m.haVirtualIPInput != nil {
		content.WriteString(m.haVirtualIPInput.View() + "\n\n")
	}
	
	// Load Balancer section
	content.WriteString(sectionStyle.Render("⚖️  Load Balancer Configuration") + "\n")
	if m.haLoadBalancerTypeSelect != nil {
		content.WriteString(m.haLoadBalancerTypeSelect.View() + "\n")
	}
	if m.haLoadBalancerPortInput != nil {
		content.WriteString(m.haLoadBalancerPortInput.View() + "\n\n")
	}
	
	// Etcd section
	content.WriteString(sectionStyle.Render("🗄️  Etcd Configuration") + "\n")
	if m.haEtcdSnapshotCountInput != nil {
		content.WriteString(m.haEtcdSnapshotCountInput.View() + "\n")
	}
	if m.haEtcdHeartbeatInput != nil {
		content.WriteString(m.haEtcdHeartbeatInput.View() + "\n")
	}
	
	// Help text
	helpStyle := lipgloss.NewStyle().
		Foreground(colors.ZtcMutedGray).
		Italic(true)
	
	content.WriteString("\n")
	content.WriteString(helpStyle.Render("💡 HA requires multiple master nodes for redundancy.\n"))
	content.WriteString(helpStyle.Render("   Virtual IP provides a single endpoint for API server access."))
	
	return content.String()
}

// Validate checks if all HA configuration is valid
func (m HAModel) Validate() error {
	// Skip validation in simple mode
	if m.session != nil && m.session.ConfigMode == utils.ConfigModeSimple {
		return nil
	}
	
	// Only validate if HA is enabled
	if m.haEnabledToggle == nil || !m.haEnabledToggle.GetValue() {
		return nil
	}
	
	// Validate HA fields
	if m.haVirtualIPInput != nil && !m.haVirtualIPInput.ValidateInput() {
		return fmt.Errorf("HA virtual IP validation failed")
	}
	if m.haLoadBalancerPortInput != nil && !m.haLoadBalancerPortInput.ValidateInput() {
		return fmt.Errorf("HA load balancer port validation failed")
	}
	if m.haEtcdSnapshotCountInput != nil && !m.haEtcdSnapshotCountInput.ValidateInput() {
		return fmt.Errorf("HA etcd snapshot count validation failed")
	}
	if m.haEtcdHeartbeatInput != nil && !m.haEtcdHeartbeatInput.ValidateInput() {
		return fmt.Errorf("HA etcd heartbeat interval validation failed")
	}
	
	return nil
}

// ApplyToTemplate applies the HA configuration to the template
func (m HAModel) ApplyToTemplate(template *utils.ClusterConfig) error {
	if template == nil {
		return nil
	}
	
	// Initialize HA config if needed
	if template.Cluster.HAConfig == nil {
		template.Cluster.HAConfig = &utils.HAConfig{}
	}
	
	// Apply HA enabled state
	if m.haEnabledToggle != nil {
		template.Cluster.HAConfig.Enabled = m.haEnabledToggle.GetValue()
		
		if template.Cluster.HAConfig.Enabled {
			// Apply virtual IP
			if m.haVirtualIPInput != nil {
				template.Cluster.HAConfig.VirtualIP = m.haVirtualIPInput.GetValue()
			}
			
			// Apply load balancer configuration
			if m.haLoadBalancerTypeSelect != nil {
				if template.Cluster.HAConfig.LoadBalancer == nil {
					template.Cluster.HAConfig.LoadBalancer = &utils.LoadBalancer{}
				}
				template.Cluster.HAConfig.LoadBalancer.Type = m.haLoadBalancerTypeSelect.GetValue()
				
				if m.haLoadBalancerPortInput != nil && m.haLoadBalancerPortInput.GetValue() != "" {
					if port, err := strconv.Atoi(m.haLoadBalancerPortInput.GetValue()); err == nil {
						template.Cluster.HAConfig.LoadBalancer.Port = port
					}
				}
			}
			
			// Apply etcd configuration
			if (m.haEtcdSnapshotCountInput != nil && m.haEtcdSnapshotCountInput.GetValue() != "") ||
				(m.haEtcdHeartbeatInput != nil && m.haEtcdHeartbeatInput.GetValue() != "") {
				if template.Cluster.HAConfig.EtcdConfig == nil {
					template.Cluster.HAConfig.EtcdConfig = &utils.EtcdConfig{}
				}
				
				if m.haEtcdSnapshotCountInput != nil && m.haEtcdSnapshotCountInput.GetValue() != "" {
					if count, err := strconv.Atoi(m.haEtcdSnapshotCountInput.GetValue()); err == nil {
						template.Cluster.HAConfig.EtcdConfig.SnapshotCount = count
					}
				}
				
				if m.haEtcdHeartbeatInput != nil && m.haEtcdHeartbeatInput.GetValue() != "" {
					template.Cluster.HAConfig.EtcdConfig.HeartbeatInterval = m.haEtcdHeartbeatInput.GetValue()
				}
			}
		}
	}
	
	return nil
}

// GetStepName returns the display name for this step
func (m HAModel) GetStepName() string {
	return "High Availability"
}

// ShouldShow returns true if this step should be shown in the given mode
func (m HAModel) ShouldShow(mode utils.ConfigurationMode) bool {
	return mode == utils.ConfigModeAdvanced // Only show in advanced mode
}

// Helper methods for focus management
func (m *HAModel) setFocus() {
	m.clearAllFocus()
	
	if len(m.fields) > 0 && m.focusedField < len(m.fields) {
		m.focusField(m.fields[m.focusedField])
	}
}

// setFocusIndex sets focus to a specific field index
func (m *HAModel) setFocusIndex(index int) {
	m.focusedField = index
	m.setFocus()
}

// getFieldIndexFromY calculates which field was clicked based on Y coordinate
func (m *HAModel) getFieldIndexFromY(y int) int {
	// Skip calculation in simple mode as it shows different content
	if m.session != nil && m.session.ConfigMode == utils.ConfigModeSimple {
		return -1
	}
	
	// Account for title and header (4 lines)
	// "High Availability Configuration" + "\n\n" + "Configure high availability..." + "\n\n"
	headerOffset := 4
	
	// Each field takes approximately 6 lines (label + box + \n\n)
	fieldHeight := 6
	
	// Calculate which field was clicked
	adjustedY := y - headerOffset
	if adjustedY < 0 {
		return -1
	}
	
	fieldIndex := adjustedY / fieldHeight
	
	// Validate field index
	if fieldIndex >= len(m.fields) {
		return -1
	}
	
	return fieldIndex
}

func (m *HAModel) clearAllFocus() {
	if m.haEnabledToggle != nil {
		m.haEnabledToggle.Blur()
	}
	if m.haVirtualIPInput != nil {
		m.haVirtualIPInput.Blur()
	}
	if m.haLoadBalancerTypeSelect != nil {
		m.haLoadBalancerTypeSelect.Blur()
	}
	if m.haLoadBalancerPortInput != nil {
		m.haLoadBalancerPortInput.Blur()
	}
	if m.haEtcdSnapshotCountInput != nil {
		m.haEtcdSnapshotCountInput.Blur()
	}
	if m.haEtcdHeartbeatInput != nil {
		m.haEtcdHeartbeatInput.Blur()
	}
}

func (m *HAModel) focusField(fieldName string) {
	switch fieldName {
	case "haEnabled":
		if m.haEnabledToggle != nil {
			m.haEnabledToggle.Focus()
		}
	case "haVirtualIP":
		if m.haVirtualIPInput != nil {
			m.haVirtualIPInput.Focus()
		}
	case "haLoadBalancerType":
		if m.haLoadBalancerTypeSelect != nil {
			m.haLoadBalancerTypeSelect.Focus()
		}
	case "haLoadBalancerPort":
		if m.haLoadBalancerPortInput != nil {
			m.haLoadBalancerPortInput.Focus()
		}
	case "haEtcdSnapshotCount":
		if m.haEtcdSnapshotCountInput != nil {
			m.haEtcdSnapshotCountInput.Focus()
		}
	case "haEtcdHeartbeat":
		if m.haEtcdHeartbeatInput != nil {
			m.haEtcdHeartbeatInput.Focus()
		}
	}
}

func (m *HAModel) nextField() {
	if len(m.fields) > 0 && m.focusedField < len(m.fields)-1 {
		m.focusedField++
		m.setFocus()
	}
}

func (m *HAModel) prevField() {
	if m.focusedField > 0 {
		m.focusedField--
		m.setFocus()
	}
}

func (m *HAModel) updateFocusedField(msg tea.Msg) tea.Cmd {
	if len(m.fields) == 0 || m.focusedField >= len(m.fields) {
		return nil
	}
	
	fieldToUpdate := m.fields[m.focusedField]
	switch fieldToUpdate {
	case "haEnabled":
		if m.haEnabledToggle != nil {
			return m.haEnabledToggle.Update(msg)
		}
	case "haVirtualIP":
		if m.haVirtualIPInput != nil {
			return m.haVirtualIPInput.Update(msg)
		}
	case "haLoadBalancerType":
		if m.haLoadBalancerTypeSelect != nil {
			return m.haLoadBalancerTypeSelect.Update(msg)
		}
	case "haLoadBalancerPort":
		if m.haLoadBalancerPortInput != nil {
			return m.haLoadBalancerPortInput.Update(msg)
		}
	case "haEtcdSnapshotCount":
		if m.haEtcdSnapshotCountInput != nil {
			return m.haEtcdSnapshotCountInput.Update(msg)
		}
	case "haEtcdHeartbeat":
		if m.haEtcdHeartbeatInput != nil {
			return m.haEtcdHeartbeatInput.Update(msg)
		}
	}
	return nil
}