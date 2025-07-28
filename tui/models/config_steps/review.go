package config_steps

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"ztc-tui/colors"
	"ztc-tui/utils"
)

// ReviewModel handles configuration review and summary
type ReviewModel struct {
	BaseStepModel
	
	// Configuration summary data
	templateMetadata *utils.TemplateMetadata
	availableBundles []utils.Bundle
}

// NewReviewModel creates a new review model
func NewReviewModel() *ReviewModel {
	return &ReviewModel{
		BaseStepModel: BaseStepModel{
			Width:  80,
			Height: 24,
		},
	}
}

// Init initializes the review model
func (m ReviewModel) Init() tea.Cmd {
	return nil
}

// InitWithConfig initializes the model with shared configuration
func (m *ReviewModel) InitWithConfig(session *utils.Session, template *utils.ClusterConfig) tea.Cmd {
	m.session = session
	m.template = template
	
	if template != nil {
		// Create metadata from template
		m.templateMetadata = &utils.TemplateMetadata{
			Name:        template.Cluster.Name,
			Description: template.Cluster.Description,
			NodeCount:   fmt.Sprintf("%d nodes", len(template.Nodes.ClusterNodes)),
		}
	}
	
	// Load available bundles for display
	m.availableBundles = utils.GetAvailableBundles()
	
	return nil
}

// Update handles messages and user input
func (m *ReviewModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	// Review is read-only, no input handling needed
	return m, nil
}

// View renders the configuration review interface
func (m ReviewModel) View() string {
	var content strings.Builder
	
	// Step title
	title := lipgloss.NewStyle().
		Foreground(colors.ZtcOrange).
		Bold(true).
		Render("Configuration Review")
	content.WriteString(title + "\n\n")
	
	if m.template == nil {
		content.WriteString("No configuration to review.\n")
		return content.String()
	}
	
	// Configuration summary
	content.WriteString("Review your cluster configuration before deployment:\n\n")
	
	// Template/Mission info
	content.WriteString(m.renderTemplateInfo() + "\n\n")
	
	// Network configuration
	content.WriteString(m.renderNetworkConfig() + "\n\n")
	
	// SSH configuration
	content.WriteString(m.renderSSHConfig() + "\n\n")
	
	// Storage configuration (advanced mode only)
	if m.session != nil && m.session.ConfigMode == utils.ConfigModeAdvanced {
		content.WriteString(m.renderStorageConfig() + "\n\n")
		
		// HA configuration (if enabled)
		if m.template.Cluster.HAConfig != nil && m.template.Cluster.HAConfig.Enabled {
			content.WriteString(m.renderHAConfig() + "\n\n")
		}
		
		// Bundle selection
		content.WriteString(m.renderBundleConfig() + "\n\n")
	}
	
	// Node information
	content.WriteString(m.renderNodeInfo() + "\n\n")
	
	// Final instructions
	instructionStyle := lipgloss.NewStyle().
		Foreground(colors.ZtcLightGray).
		Border(lipgloss.RoundedBorder()).
		Padding(1).
		BorderForeground(colors.ZtcOrange)
	
	instruction := "✅ Configuration ready!\n\nPress Enter to continue to USB creation."
	content.WriteString(instructionStyle.Render(instruction))
	
	return content.String()
}

// renderTemplateInfo renders template/mission information
func (m ReviewModel) renderTemplateInfo() string {
	var content strings.Builder
	
	sectionStyle := lipgloss.NewStyle().
		Foreground(colors.ZtcOrange).
		Bold(true).
		Underline(true)
	
	content.WriteString(sectionStyle.Render("🎯 Mission") + "\n")
	
	if m.templateMetadata != nil {
		content.WriteString(fmt.Sprintf("Name: %s\n", m.templateMetadata.Name))
		if m.templateMetadata.Description != "" {
			content.WriteString(fmt.Sprintf("Description: %s\n", m.templateMetadata.Description))
		}
		content.WriteString(fmt.Sprintf("Node Count: %s", m.templateMetadata.NodeCount))
	}
	
	return content.String()
}

// renderNetworkConfig renders network configuration summary
func (m ReviewModel) renderNetworkConfig() string {
	var content strings.Builder
	
	sectionStyle := lipgloss.NewStyle().
		Foreground(colors.ZtcOrange).
		Bold(true).
		Underline(true)
	
	content.WriteString(sectionStyle.Render("🌐 Network Configuration") + "\n")
	content.WriteString(fmt.Sprintf("Cluster Name: %s\n", m.template.Cluster.Name))
	content.WriteString(fmt.Sprintf("Network Subnet: %s\n", m.template.Network.Subnet))
	content.WriteString(fmt.Sprintf("Gateway: %s\n", m.template.Network.Gateway))
	
	// Show advanced network config only in advanced mode
	if m.session != nil && m.session.ConfigMode == utils.ConfigModeAdvanced {
		content.WriteString(fmt.Sprintf("Pod CIDR: %s\n", m.template.Network.PodCIDR))
		content.WriteString(fmt.Sprintf("Service CIDR: %s\n", m.template.Network.ServiceCIDR))
	}
	
	content.WriteString(fmt.Sprintf("DNS Domain: %s", m.template.Network.DNS.Domain))
	
	if len(m.template.Network.DNS.Upstreams) > 0 {
		content.WriteString(fmt.Sprintf("\nDNS Upstreams: %s", strings.Join(m.template.Network.DNS.Upstreams, ", ")))
	}
	
	return content.String()
}

// renderSSHConfig renders SSH configuration summary
func (m ReviewModel) renderSSHConfig() string {
	var content strings.Builder
	
	sectionStyle := lipgloss.NewStyle().
		Foreground(colors.ZtcOrange).
		Bold(true).
		Underline(true)
	
	content.WriteString(sectionStyle.Render("🔑 SSH Configuration") + "\n")
	content.WriteString(fmt.Sprintf("SSH Username: %s\n", m.template.Nodes.SSH.Username))
	content.WriteString(fmt.Sprintf("SSH Public Key: %s\n", m.template.Nodes.SSH.PublicKeyPath))
	content.WriteString(fmt.Sprintf("SSH Private Key: %s", m.template.Nodes.SSH.PrivateKeyPath))
	
	return content.String()
}

// renderStorageConfig renders storage configuration summary
func (m ReviewModel) renderStorageConfig() string {
	var content strings.Builder
	
	sectionStyle := lipgloss.NewStyle().
		Foreground(colors.ZtcOrange).
		Bold(true).
		Underline(true)
	
	content.WriteString(sectionStyle.Render("💾 Storage Configuration") + "\n")
	content.WriteString(fmt.Sprintf("Default Storage Class: %s\n", m.template.Storage.DefaultStorageClass))
	
	if m.template.Storage.LocalPath.Enabled {
		content.WriteString("LocalPath: Enabled\n")
	}
	
	if m.template.Storage.Longhorn.Enabled {
		content.WriteString("Longhorn: Enabled")
		if m.template.Storage.Longhorn.ReplicaCount > 0 {
			content.WriteString(fmt.Sprintf(" (Replicas: %d)", m.template.Storage.Longhorn.ReplicaCount))
		}
		content.WriteString("\n")
	}
	
	if m.template.Storage.NFS.Enabled {
		content.WriteString("NFS: Enabled")
		if m.template.Storage.NFS.StorageSize != "" {
			content.WriteString(fmt.Sprintf(" (Size: %s)", m.template.Storage.NFS.StorageSize))
		}
		content.WriteString("\n")
	}
	
	return strings.TrimSuffix(content.String(), "\n")
}

// renderHAConfig renders HA configuration summary
func (m ReviewModel) renderHAConfig() string {
	var content strings.Builder
	
	sectionStyle := lipgloss.NewStyle().
		Foreground(colors.ZtcOrange).
		Bold(true).
		Underline(true)
	
	content.WriteString(sectionStyle.Render("⚡ High Availability Configuration") + "\n")
	content.WriteString("HA Enabled: Yes\n")
	
	if m.template.Cluster.HAConfig.VirtualIP != "" {
		content.WriteString(fmt.Sprintf("Virtual IP: %s\n", m.template.Cluster.HAConfig.VirtualIP))
	}
	
	if m.template.Cluster.HAConfig.LoadBalancer != nil {
		content.WriteString(fmt.Sprintf("Load Balancer Type: %s", m.template.Cluster.HAConfig.LoadBalancer.Type))
		if m.template.Cluster.HAConfig.LoadBalancer.Port > 0 {
			content.WriteString(fmt.Sprintf(" (Port: %d)", m.template.Cluster.HAConfig.LoadBalancer.Port))
		}
		content.WriteString("\n")
	}
	
	if m.template.Cluster.HAConfig.EtcdConfig != nil {
		if m.template.Cluster.HAConfig.EtcdConfig.SnapshotCount > 0 {
			content.WriteString(fmt.Sprintf("Etcd Snapshot Count: %d\n", m.template.Cluster.HAConfig.EtcdConfig.SnapshotCount))
		}
		if m.template.Cluster.HAConfig.EtcdConfig.HeartbeatInterval != "" {
			content.WriteString(fmt.Sprintf("Etcd Heartbeat Interval: %s", m.template.Cluster.HAConfig.EtcdConfig.HeartbeatInterval))
		}
	}
	
	return content.String()
}

// renderBundleConfig renders bundle selection summary
func (m ReviewModel) renderBundleConfig() string {
	var content strings.Builder
	
	sectionStyle := lipgloss.NewStyle().
		Foreground(colors.ZtcOrange).
		Bold(true).
		Underline(true)
	
	content.WriteString(sectionStyle.Render("📦 Auto-Deploy Bundles") + "\n")
	
	if len(m.template.Workloads.AutoDeployBundles) == 0 {
		content.WriteString("None selected")
		return content.String()
	}
	
	// Map bundle IDs to names
	bundleNames := make(map[string]string)
	for _, bundle := range m.availableBundles {
		bundleNames[bundle.ID] = bundle.Name
	}
	
	var selectedNames []string
	for _, bundleID := range m.template.Workloads.AutoDeployBundles {
		if name, exists := bundleNames[bundleID]; exists {
			selectedNames = append(selectedNames, name)
		} else {
			selectedNames = append(selectedNames, bundleID)
		}
	}
	
	content.WriteString(strings.Join(selectedNames, ", "))
	
	return content.String()
}

// renderNodeInfo renders node information
func (m ReviewModel) renderNodeInfo() string {
	var content strings.Builder
	
	sectionStyle := lipgloss.NewStyle().
		Foreground(colors.ZtcOrange).
		Bold(true).
		Underline(true)
	
	content.WriteString(sectionStyle.Render("🖥️  Cluster Nodes") + "\n")
	
	if len(m.template.Nodes.ClusterNodes) == 0 {
		content.WriteString("No nodes configured")
		return content.String()
	}
	
	for hostname, node := range m.template.Nodes.ClusterNodes {
		content.WriteString(fmt.Sprintf("• %s: %s (%s)\n", hostname, node.IP, node.Role))
	}
	
	return strings.TrimSuffix(content.String(), "\n")
}

// Validate checks if review is valid (always true for review)
func (m ReviewModel) Validate() error {
	return nil // Review is always valid
}

// ApplyToTemplate applies no changes (review is read-only)
func (m ReviewModel) ApplyToTemplate(template *utils.ClusterConfig) error {
	return nil // No changes to apply
}

// GetStepName returns the display name for this step
func (m ReviewModel) GetStepName() string {
	if m.session != nil && m.session.ConfigMode == utils.ConfigModeSimple {
		return "Deploy Preview"
	}
	return "Final Review"
}

// ShouldShow returns true if this step should be shown in the given mode
func (m ReviewModel) ShouldShow(mode utils.ConfigurationMode) bool {
	return true // Review is always shown
}