package config_steps

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"ztc-tui/colors"
	"ztc-tui/components"
	"ztc-tui/utils"
	"ztc-tui/validation"
)

// NetworkModel handles cluster name and network configuration
type NetworkModel struct {
	BaseStepModel
	
	// Network configuration components
	clusterNameInput   *components.InputField
	networkSubnetInput *components.InputField
	gatewayInput       *components.InputField
	podCIDRInput       *components.InputField
	serviceCIDRInput   *components.InputField
	dnsDomainInput     *components.InputField
	dnsUpstreamsInput  *components.InputField
	
	// UI state
	focusedField int
	fields       []string
}

// NewNetworkModel creates a new network configuration model
func NewNetworkModel() *NetworkModel {
	return &NetworkModel{
		BaseStepModel: BaseStepModel{
			Width:  80,
			Height: 24,
		},
		fields: []string{
			"clusterName",
			"networkSubnet", 
			"gateway",
			"podCIDR",
			"serviceCIDR",
			"dnsDomain",
			"dnsUpstreams",
		},
	}
}

// Init initializes the network model
func (m NetworkModel) Init() tea.Cmd {
	return nil
}

// InitWithConfig initializes the model with shared configuration
func (m *NetworkModel) InitWithConfig(session *utils.Session, template *utils.ClusterConfig) tea.Cmd {
	m.session = session
	m.template = template
	
	if template == nil {
		return nil
	}
	
	// Initialize input fields with template values
	m.clusterNameInput = components.NewInputField("Cluster Name", template.Cluster.Name, 40)
	m.clusterNameInput.SetValue(template.Cluster.Name)
	m.clusterNameInput.Validate = validation.ValidateClusterName
	
	m.networkSubnetInput = components.NewInputField("Network Subnet", template.Network.Subnet, 40)
	m.networkSubnetInput.SetValue(template.Network.Subnet)
	m.networkSubnetInput.Validate = validation.ValidateNetworkSubnet
	
	m.gatewayInput = components.NewInputField("Gateway IP", template.Network.Gateway, 40)
	m.gatewayInput.SetValue(template.Network.Gateway)
	m.gatewayInput.Validate = validation.ValidateGateway
	
	m.podCIDRInput = components.NewInputField("Pod CIDR", template.Network.PodCIDR, 40)
	m.podCIDRInput.SetValue(template.Network.PodCIDR)
	m.podCIDRInput.Validate = validation.ValidatePodCIDR
	
	m.serviceCIDRInput = components.NewInputField("Service CIDR", template.Network.ServiceCIDR, 40)
	m.serviceCIDRInput.SetValue(template.Network.ServiceCIDR)
	m.serviceCIDRInput.Validate = validation.ValidateServiceCIDR
	
	m.dnsDomainInput = components.NewInputField("DNS Domain", template.Network.DNS.Domain, 40)
	m.dnsDomainInput.SetValue(template.Network.DNS.Domain)
	m.dnsDomainInput.Validate = validation.ValidateDNSDomain
	
	// Join DNS upstreams for display
	dnsUpstreams := strings.Join(template.Network.DNS.Upstreams, ", ")
	m.dnsUpstreamsInput = components.NewInputField("DNS Upstreams (comma-separated)", dnsUpstreams, 50)
	m.dnsUpstreamsInput.SetValue(dnsUpstreams)
	m.dnsUpstreamsInput.Validate = validation.ValidateDNSUpstreams
	
	// Set initial focus
	m.setFocus()
	
	return nil
}

// Update handles messages and user input
func (m NetworkModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
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
	}
	
	return m, tea.Batch(cmds...)
}

// View renders the network configuration interface
func (m NetworkModel) View() string {
	var content strings.Builder
	
	// Step title
	title := lipgloss.NewStyle().
		Foreground(colors.ZtcOrange).
		Bold(true).
		Render("Network & Cluster Configuration")
	content.WriteString(title + "\n\n")
	
	// Simple vs Advanced mode different layouts
	if m.session != nil && m.session.ConfigMode == utils.ConfigModeSimple {
		content.WriteString(m.renderSimpleMode())
	} else {
		content.WriteString(m.renderAdvancedMode())
	}
	
	return content.String()
}

// renderSimpleMode renders fields for simple configuration mode
func (m NetworkModel) renderSimpleMode() string {
	var content strings.Builder
	
	content.WriteString("Essential cluster settings:\n\n")
	
	// Show only essential fields in simple mode
	if m.clusterNameInput != nil {
		content.WriteString(m.clusterNameInput.View() + "\n\n")
	}
	if m.networkSubnetInput != nil {
		content.WriteString(m.networkSubnetInput.View() + "\n\n")
	}
	if m.gatewayInput != nil {
		content.WriteString(m.gatewayInput.View() + "\n\n")
	}
	if m.dnsDomainInput != nil {
		content.WriteString(m.dnsDomainInput.View() + "\n")
	}
	
	return content.String()
}

// renderAdvancedMode renders all fields for advanced configuration mode
func (m NetworkModel) renderAdvancedMode() string {
	var content strings.Builder
	
	content.WriteString("Complete network configuration:\n\n")
	
	// Show all fields in advanced mode
	if m.clusterNameInput != nil {
		content.WriteString(m.clusterNameInput.View() + "\n\n")
	}
	if m.networkSubnetInput != nil {
		content.WriteString(m.networkSubnetInput.View() + "\n\n")
	}
	if m.gatewayInput != nil {
		content.WriteString(m.gatewayInput.View() + "\n\n")
	}
	if m.podCIDRInput != nil {
		content.WriteString(m.podCIDRInput.View() + "\n\n")
	}
	if m.serviceCIDRInput != nil {
		content.WriteString(m.serviceCIDRInput.View() + "\n\n")
	}
	if m.dnsDomainInput != nil {
		content.WriteString(m.dnsDomainInput.View() + "\n\n")
	}
	if m.dnsUpstreamsInput != nil {
		content.WriteString(m.dnsUpstreamsInput.View() + "\n")
	}
	
	return content.String()
}

// Validate checks if all network configuration is valid
func (m NetworkModel) Validate() error {
	// Validate all fields
	if m.clusterNameInput != nil && !m.clusterNameInput.ValidateInput() {
		return fmt.Errorf("cluster name validation failed")
	}
	if m.networkSubnetInput != nil && !m.networkSubnetInput.ValidateInput() {
		return fmt.Errorf("network subnet validation failed")
	}
	if m.gatewayInput != nil && !m.gatewayInput.ValidateInput() {
		return fmt.Errorf("gateway validation failed")
	}
	if m.podCIDRInput != nil && !m.podCIDRInput.ValidateInput() {
		return fmt.Errorf("pod CIDR validation failed")
	}
	if m.serviceCIDRInput != nil && !m.serviceCIDRInput.ValidateInput() {
		return fmt.Errorf("service CIDR validation failed")
	}
	if m.dnsDomainInput != nil && !m.dnsDomainInput.ValidateInput() {
		return fmt.Errorf("DNS domain validation failed")
	}
	if m.dnsUpstreamsInput != nil && !m.dnsUpstreamsInput.ValidateInput() {
		return fmt.Errorf("DNS upstreams validation failed")
	}
	
	// Cross-field network validation
	var subnet, gateway, podCIDR, serviceCIDR string
	if m.networkSubnetInput != nil {
		subnet = m.networkSubnetInput.GetValue()
	}
	if m.gatewayInput != nil {
		gateway = m.gatewayInput.GetValue()
	}
	if m.podCIDRInput != nil {
		podCIDR = m.podCIDRInput.GetValue()
	}
	if m.serviceCIDRInput != nil {
		serviceCIDR = m.serviceCIDRInput.GetValue()
	}
	
	// Validate gateway is within subnet
	if err := validation.ValidateGatewayInSubnet(gateway, subnet); err != nil {
		return err
	}
	
	// Validate network overlaps
	if err := validation.ValidateNetworkOverlaps(subnet, podCIDR, serviceCIDR); err != nil {
		return err
	}
	
	return nil
}

// ApplyToTemplate applies the network configuration to the template
func (m NetworkModel) ApplyToTemplate(template *utils.ClusterConfig) error {
	if template == nil {
		return nil
	}
	
	// Apply cluster name
	if m.clusterNameInput != nil {
		template.Cluster.Name = m.clusterNameInput.GetValue()
	}
	
	// Apply network configuration
	if m.networkSubnetInput != nil {
		template.Network.Subnet = m.networkSubnetInput.GetValue()
	}
	if m.gatewayInput != nil {
		template.Network.Gateway = m.gatewayInput.GetValue()
	}
	if m.podCIDRInput != nil {
		template.Network.PodCIDR = m.podCIDRInput.GetValue()
	}
	if m.serviceCIDRInput != nil {
		template.Network.ServiceCIDR = m.serviceCIDRInput.GetValue()
	}
	if m.dnsDomainInput != nil {
		template.Network.DNS.Domain = m.dnsDomainInput.GetValue()
	}
	
	// Parse and apply DNS upstreams
	if m.dnsUpstreamsInput != nil {
		upstreamsStr := m.dnsUpstreamsInput.GetValue()
		if upstreamsStr != "" {
			upstreams := strings.Split(upstreamsStr, ",")
			var filteredUpstreams []string
			for _, upstream := range upstreams {
				upstream = strings.TrimSpace(upstream)
				if upstream != "" {
					filteredUpstreams = append(filteredUpstreams, upstream)
				}
			}
			template.Network.DNS.Upstreams = filteredUpstreams
		}
	}
	
	return nil
}

// GetStepName returns the display name for this step
func (m NetworkModel) GetStepName() string {
	if m.session != nil && m.session.ConfigMode == utils.ConfigModeSimple {
		return "Network Essentials"
	}
	return "Network Configuration"
}

// ShouldShow returns true if this step should be shown in the given mode
func (m NetworkModel) ShouldShow(mode utils.ConfigurationMode) bool {
	return true // Network configuration is always shown
}

// Helper methods for focus management
func (m *NetworkModel) setFocus() {
	m.clearAllFocus()
	
	// Get fields for current mode
	var fields []string
	if m.session != nil && m.session.ConfigMode == utils.ConfigModeSimple {
		fields = []string{"clusterName", "networkSubnet", "gateway", "dnsDomain"}
	} else {
		fields = m.fields
	}
	
	if len(fields) > 0 && m.focusedField < len(fields) {
		m.focusField(fields[m.focusedField])
	}
}

func (m *NetworkModel) clearAllFocus() {
	if m.clusterNameInput != nil {
		m.clusterNameInput.Blur()
	}
	if m.networkSubnetInput != nil {
		m.networkSubnetInput.Blur()
	}
	if m.gatewayInput != nil {
		m.gatewayInput.Blur()
	}
	if m.podCIDRInput != nil {
		m.podCIDRInput.Blur()
	}
	if m.serviceCIDRInput != nil {
		m.serviceCIDRInput.Blur()
	}
	if m.dnsDomainInput != nil {
		m.dnsDomainInput.Blur()
	}
	if m.dnsUpstreamsInput != nil {
		m.dnsUpstreamsInput.Blur()
	}
}

func (m *NetworkModel) focusField(fieldName string) {
	switch fieldName {
	case "clusterName":
		if m.clusterNameInput != nil {
			m.clusterNameInput.Focus()
		}
	case "networkSubnet":
		if m.networkSubnetInput != nil {
			m.networkSubnetInput.Focus()
		}
	case "gateway":
		if m.gatewayInput != nil {
			m.gatewayInput.Focus()
		}
	case "podCIDR":
		if m.podCIDRInput != nil {
			m.podCIDRInput.Focus()
		}
	case "serviceCIDR":
		if m.serviceCIDRInput != nil {
			m.serviceCIDRInput.Focus()
		}
	case "dnsDomain":
		if m.dnsDomainInput != nil {
			m.dnsDomainInput.Focus()
		}
	case "dnsUpstreams":
		if m.dnsUpstreamsInput != nil {
			m.dnsUpstreamsInput.Focus()
		}
	}
}

func (m *NetworkModel) nextField() {
	// Get fields for current mode
	var fields []string
	if m.session != nil && m.session.ConfigMode == utils.ConfigModeSimple {
		fields = []string{"clusterName", "networkSubnet", "gateway", "dnsDomain"}
	} else {
		fields = m.fields
	}
	
	if len(fields) > 0 && m.focusedField < len(fields)-1 {
		m.focusedField++
		m.setFocus()
	}
}

func (m *NetworkModel) prevField() {
	if m.focusedField > 0 {
		m.focusedField--
		m.setFocus()
	}
}

func (m *NetworkModel) updateFocusedField(msg tea.Msg) tea.Cmd {
	// Get fields for current mode
	var fields []string
	if m.session != nil && m.session.ConfigMode == utils.ConfigModeSimple {
		fields = []string{"clusterName", "networkSubnet", "gateway", "dnsDomain"}
	} else {
		fields = m.fields
	}
	
	if len(fields) == 0 || m.focusedField >= len(fields) {
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
	case "gateway":
		if m.gatewayInput != nil {
			return m.gatewayInput.Update(msg)
		}
	case "podCIDR":
		if m.podCIDRInput != nil {
			return m.podCIDRInput.Update(msg)
		}
	case "serviceCIDR":
		if m.serviceCIDRInput != nil {
			return m.serviceCIDRInput.Update(msg)
		}
	case "dnsDomain":
		if m.dnsDomainInput != nil {
			return m.dnsDomainInput.Update(msg)
		}
	case "dnsUpstreams":
		if m.dnsUpstreamsInput != nil {
			return m.dnsUpstreamsInput.Update(msg)
		}
	}
	return nil
}