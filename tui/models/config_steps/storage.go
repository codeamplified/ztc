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

// StorageModel handles storage configuration
type StorageModel struct {
	BaseStepModel
	
	// Storage configuration components
	storageDefaultClassSelect   *components.SelectField
	localPathEnabledToggle      *components.ToggleField
	longhornEnabledToggle       *components.ToggleField
	longhornNamespaceInput      *components.InputField
	longhornReplicaCountInput   *components.InputField
	longhornStorageClassInput   *components.InputField
	longhornReclaimPolicySelect *components.SelectField
	longhornBackupTargetInput   *components.InputField
	longhornDataPathInput       *components.InputField
	nfsEnabledToggle            *components.ToggleField
	nfsNamespaceInput           *components.InputField
	nfsBackendStorageInput      *components.SelectField
	nfsStorageSizeInput         *components.InputField
	nfsStorageClassInput        *components.InputField
	
	// UI state
	focusedField int
	fields       []string
}

// NewStorageModel creates a new storage configuration model
func NewStorageModel() *StorageModel {
	return &StorageModel{
		BaseStepModel: BaseStepModel{
			Width:  80,
			Height: 24,
		},
		fields: []string{
			"storageDefaultClass",
			"localPathEnabled",
			"longhornEnabled",
			"longhornNamespace",
			"longhornReplicaCount",
			"longhornStorageClass",
			"longhornReclaimPolicy",
			"longhornBackupTarget",
			"longhornDataPath",
			"nfsEnabled",
			"nfsNamespace",
			"nfsBackendStorage",
			"nfsStorageSize",
			"nfsStorageClass",
		},
	}
}

// Init initializes the storage model
func (m StorageModel) Init() tea.Cmd {
	return nil
}

// InitWithConfig initializes the model with shared configuration
func (m *StorageModel) InitWithConfig(session *utils.Session, template *utils.ClusterConfig) tea.Cmd {
	m.session = session
	m.template = template
	
	if template == nil {
		return nil
	}
	
	// Initialize storage configuration fields
	storageClasses := []string{"local-path", "longhorn", "nfs-client"}
	m.storageDefaultClassSelect = components.NewSelectField("Default Storage Class", storageClasses, 40)
	m.storageDefaultClassSelect.SetValue(template.Storage.DefaultStorageClass)
	
	// LocalPath configuration
	m.localPathEnabledToggle = components.NewToggleField("Enable LocalPath (built-in k3s storage)", template.Storage.LocalPath.Enabled)
	
	// Longhorn configuration
	m.longhornEnabledToggle = components.NewToggleField("Enable Longhorn (distributed block storage)", template.Storage.Longhorn.Enabled)
	m.longhornNamespaceInput = components.NewInputField("Longhorn Namespace", "longhorn-system", 30)
	m.longhornNamespaceInput.SetValue(getStringValueOrDefault(template.Storage.Longhorn.Namespace, "longhorn-system"))
	
	m.longhornReplicaCountInput = components.NewInputField("Replica Count", "3", 10)
	m.longhornReplicaCountInput.SetValue(fmt.Sprintf("%d", getIntValueOrDefault(template.Storage.Longhorn.ReplicaCount, 3)))
	m.longhornReplicaCountInput.Validate = validation.ValidateReplicaCount
	
	m.longhornStorageClassInput = components.NewInputField("Storage Class Name", "longhorn", 30)
	m.longhornStorageClassInput.SetValue(getStringValueOrDefault(template.Storage.Longhorn.StorageClass.Name, "longhorn"))
	
	reclaimPolicies := []string{"Retain", "Delete"}
	m.longhornReclaimPolicySelect = components.NewSelectField("Reclaim Policy", reclaimPolicies, 20)
	m.longhornReclaimPolicySelect.SetValue(getStringValueOrDefault(template.Storage.Longhorn.StorageClass.ReclaimPolicy, "Retain"))
	
	m.longhornBackupTargetInput = components.NewInputField("Backup Target (optional)", "", 50)
	m.longhornBackupTargetInput.SetValue(template.Storage.Longhorn.Settings.BackupTarget)
	
	m.longhornDataPathInput = components.NewInputField("Data Path", "/var/lib/longhorn", 50)
	m.longhornDataPathInput.SetValue(getStringValueOrDefault(template.Storage.Longhorn.Settings.DefaultDataPath, "/var/lib/longhorn"))
	m.longhornDataPathInput.Validate = validation.ValidatePath
	
	// NFS configuration
	m.nfsEnabledToggle = components.NewToggleField("Enable NFS (network file system)", template.Storage.NFS.Enabled)
	m.nfsNamespaceInput = components.NewInputField("NFS Namespace", "nfs-system", 30)
	m.nfsNamespaceInput.SetValue(getStringValueOrDefault(template.Storage.NFS.Namespace, "nfs-system"))
	
	backendStorageClasses := []string{"local-path", "longhorn"}
	m.nfsBackendStorageInput = components.NewSelectField("Backend Storage Class", backendStorageClasses, 30)
	m.nfsBackendStorageInput.SetValue(getStringValueOrDefault(template.Storage.NFS.BackendStorageClass, "local-path"))
	
	m.nfsStorageSizeInput = components.NewInputField("Storage Size", "100Gi", 20)
	m.nfsStorageSizeInput.SetValue(getStringValueOrDefault(template.Storage.NFS.StorageSize, "100Gi"))
	m.nfsStorageSizeInput.Validate = validation.ValidateStorageSize
	
	m.nfsStorageClassInput = components.NewInputField("NFS Storage Class Name", "nfs-client", 30)
	m.nfsStorageClassInput.SetValue(getStringValueOrDefault(template.Storage.NFS.StorageClass.Name, "nfs-client"))
	
	// Set initial focus
	m.setFocus()
	
	return nil
}

// Update handles messages and user input
func (m *StorageModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
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

// View renders the storage configuration interface
func (m StorageModel) View() string {
	var content strings.Builder
	
	// Step title
	title := lipgloss.NewStyle().
		Foreground(colors.ZtcOrange).
		Bold(true).
		Render("Storage Configuration")
	content.WriteString(title + "\n\n")
	
	// Only show in advanced mode
	if m.session != nil && m.session.ConfigMode == utils.ConfigModeSimple {
		content.WriteString("Storage configuration is managed automatically in Simple mode.\n")
		content.WriteString("LocalPath storage will be used by default.\n\n")
		content.WriteString("Switch to Advanced mode (press 'M') for full storage configuration.")
		return content.String()
	}
	
	content.WriteString("Configure storage backends for your cluster:\n\n")
	
	// Default storage class
	if m.storageDefaultClassSelect != nil {
		content.WriteString(m.storageDefaultClassSelect.View() + "\n\n")
	}
	
	// LocalPath section
	content.WriteString(m.renderLocalPathSection() + "\n\n")
	
	// Longhorn section
	content.WriteString(m.renderLonghornSection() + "\n\n")
	
	// NFS section
	content.WriteString(m.renderNFSSection())
	
	return content.String()
}

// renderLocalPathSection renders the LocalPath storage section
func (m StorageModel) renderLocalPathSection() string {
	var content strings.Builder
	
	sectionStyle := lipgloss.NewStyle().
		Foreground(colors.ZtcLightGray).
		Bold(true)
	
	content.WriteString(sectionStyle.Render("📁 LocalPath Storage") + "\n")
	if m.localPathEnabledToggle != nil {
		content.WriteString(m.localPathEnabledToggle.View())
	}
	
	return content.String()
}

// renderLonghornSection renders the Longhorn storage section
func (m StorageModel) renderLonghornSection() string {
	var content strings.Builder
	
	sectionStyle := lipgloss.NewStyle().
		Foreground(colors.ZtcLightGray).
		Bold(true)
	
	content.WriteString(sectionStyle.Render("🐄 Longhorn Storage") + "\n")
	if m.longhornEnabledToggle != nil {
		content.WriteString(m.longhornEnabledToggle.View() + "\n")
		
		// Show Longhorn fields only if enabled
		if m.longhornEnabledToggle.GetValue() {
			if m.longhornNamespaceInput != nil {
				content.WriteString(m.longhornNamespaceInput.View() + "\n")
			}
			if m.longhornReplicaCountInput != nil {
				content.WriteString(m.longhornReplicaCountInput.View() + "\n")
			}
			if m.longhornStorageClassInput != nil {
				content.WriteString(m.longhornStorageClassInput.View() + "\n")
			}
			if m.longhornReclaimPolicySelect != nil {
				content.WriteString(m.longhornReclaimPolicySelect.View() + "\n")
			}
			if m.longhornBackupTargetInput != nil {
				content.WriteString(m.longhornBackupTargetInput.View() + "\n")
			}
			if m.longhornDataPathInput != nil {
				content.WriteString(m.longhornDataPathInput.View())
			}
		}
	}
	
	return content.String()
}

// renderNFSSection renders the NFS storage section
func (m StorageModel) renderNFSSection() string {
	var content strings.Builder
	
	sectionStyle := lipgloss.NewStyle().
		Foreground(colors.ZtcLightGray).
		Bold(true)
	
	content.WriteString(sectionStyle.Render("🗂️  NFS Storage") + "\n")
	if m.nfsEnabledToggle != nil {
		content.WriteString(m.nfsEnabledToggle.View() + "\n")
		
		// Show NFS fields only if enabled
		if m.nfsEnabledToggle.GetValue() {
			if m.nfsNamespaceInput != nil {
				content.WriteString(m.nfsNamespaceInput.View() + "\n")
			}
			if m.nfsBackendStorageInput != nil {
				content.WriteString(m.nfsBackendStorageInput.View() + "\n")
			}
			if m.nfsStorageSizeInput != nil {
				content.WriteString(m.nfsStorageSizeInput.View() + "\n")
			}
			if m.nfsStorageClassInput != nil {
				content.WriteString(m.nfsStorageClassInput.View())
			}
		}
	}
	
	return content.String()
}

// Validate checks if all storage configuration is valid
func (m StorageModel) Validate() error {
	// Skip validation in simple mode
	if m.session != nil && m.session.ConfigMode == utils.ConfigModeSimple {
		return nil
	}
	
	// Validate Longhorn fields if enabled
	if m.longhornEnabledToggle != nil && m.longhornEnabledToggle.GetValue() {
		if m.longhornReplicaCountInput != nil && !m.longhornReplicaCountInput.ValidateInput() {
			return fmt.Errorf("Longhorn replica count validation failed")
		}
		if m.longhornDataPathInput != nil && !m.longhornDataPathInput.ValidateInput() {
			return fmt.Errorf("Longhorn data path validation failed")
		}
	}
	
	// Validate NFS fields if enabled
	if m.nfsEnabledToggle != nil && m.nfsEnabledToggle.GetValue() {
		if m.nfsStorageSizeInput != nil && !m.nfsStorageSizeInput.ValidateInput() {
			return fmt.Errorf("NFS storage size validation failed")
		}
	}
	
	// Additional cross-validation
	return m.validateStorageConfiguration()
}

// validateStorageConfiguration performs cross-provider storage validation
func (m StorageModel) validateStorageConfiguration() error {
	localPathEnabled := m.localPathEnabledToggle != nil && m.localPathEnabledToggle.GetValue()
	longhornEnabled := m.longhornEnabledToggle != nil && m.longhornEnabledToggle.GetValue()
	nfsEnabled := m.nfsEnabledToggle != nil && m.nfsEnabledToggle.GetValue()
	
	// At least one storage provider must be enabled
	if !localPathEnabled && !longhornEnabled && !nfsEnabled {
		return fmt.Errorf("at least one storage provider must be enabled")
	}
	
	// NFS requires a backend storage provider
	if nfsEnabled && !localPathEnabled && !longhornEnabled {
		return fmt.Errorf("NFS requires a backend storage provider (LocalPath or Longhorn)")
	}
	
	// Validate default storage class is available
	if m.storageDefaultClassSelect != nil {
		defaultClass := m.storageDefaultClassSelect.GetValue()
		switch defaultClass {
		case "local-path":
			if !localPathEnabled {
				return fmt.Errorf("default storage class 'local-path' is not enabled")
			}
		case "longhorn":
			if !longhornEnabled {
				return fmt.Errorf("default storage class 'longhorn' is not enabled")
			}
		case "nfs-client":
			if !nfsEnabled {
				return fmt.Errorf("default storage class 'nfs-client' is not enabled")
			}
		}
	}
	
	return nil
}

// ApplyToTemplate applies the storage configuration to the template
func (m StorageModel) ApplyToTemplate(template *utils.ClusterConfig) error {
	if template == nil {
		return nil
	}
	
	// Apply default storage class
	if m.storageDefaultClassSelect != nil {
		template.Storage.DefaultStorageClass = m.storageDefaultClassSelect.GetValue()
	}
	
	// Apply LocalPath configuration
	if m.localPathEnabledToggle != nil {
		template.Storage.LocalPath.Enabled = m.localPathEnabledToggle.GetValue()
	}
	
	// Apply Longhorn configuration
	if m.longhornEnabledToggle != nil {
		template.Storage.Longhorn.Enabled = m.longhornEnabledToggle.GetValue()
		if m.longhornEnabledToggle.GetValue() {
			if m.longhornNamespaceInput != nil {
				template.Storage.Longhorn.Namespace = m.longhornNamespaceInput.GetValue()
			}
			if m.longhornReplicaCountInput != nil {
				if count, err := validation.ParseReplicaCount(m.longhornReplicaCountInput.GetValue()); err == nil {
					template.Storage.Longhorn.ReplicaCount = count
				}
			}
			if m.longhornStorageClassInput != nil {
				template.Storage.Longhorn.StorageClass.Name = m.longhornStorageClassInput.GetValue()
			}
			if m.longhornReclaimPolicySelect != nil {
				template.Storage.Longhorn.StorageClass.ReclaimPolicy = m.longhornReclaimPolicySelect.GetValue()
			}
			if m.longhornBackupTargetInput != nil {
				template.Storage.Longhorn.Settings.BackupTarget = m.longhornBackupTargetInput.GetValue()
			}
			if m.longhornDataPathInput != nil {
				template.Storage.Longhorn.Settings.DefaultDataPath = m.longhornDataPathInput.GetValue()
			}
		}
	}
	
	// Apply NFS configuration
	if m.nfsEnabledToggle != nil {
		template.Storage.NFS.Enabled = m.nfsEnabledToggle.GetValue()
		if m.nfsEnabledToggle.GetValue() {
			if m.nfsNamespaceInput != nil {
				template.Storage.NFS.Namespace = m.nfsNamespaceInput.GetValue()
			}
			if m.nfsBackendStorageInput != nil {
				template.Storage.NFS.BackendStorageClass = m.nfsBackendStorageInput.GetValue()
			}
			if m.nfsStorageSizeInput != nil {
				template.Storage.NFS.StorageSize = m.nfsStorageSizeInput.GetValue()
			}
			if m.nfsStorageClassInput != nil {
				template.Storage.NFS.StorageClass.Name = m.nfsStorageClassInput.GetValue()
			}
		}
	}
	
	return nil
}

// GetStepName returns the display name for this step
func (m StorageModel) GetStepName() string {
	return "Storage Configuration"
}

// ShouldShow returns true if this step should be shown in the given mode
func (m StorageModel) ShouldShow(mode utils.ConfigurationMode) bool {
	return mode == utils.ConfigModeAdvanced // Only show in advanced mode
}

// Helper functions
func getStringValueOrDefault(value, defaultValue string) string {
	if value == "" {
		return defaultValue
	}
	return value
}

func getIntValueOrDefault(value, defaultValue int) int {
	if value == 0 {
		return defaultValue
	}
	return value
}

// Helper methods for focus management
func (m *StorageModel) setFocus() {
	m.clearAllFocus()
	
	if len(m.fields) > 0 && m.focusedField < len(m.fields) {
		m.focusField(m.fields[m.focusedField])
	}
}

// setFocusIndex sets focus to a specific field index
func (m *StorageModel) setFocusIndex(index int) {
	m.focusedField = index
	m.setFocus()
}

// getFieldIndexFromY calculates which field was clicked based on Y coordinate
func (m *StorageModel) getFieldIndexFromY(y int) int {
	// Skip calculation in simple mode as it shows different content
	if m.session != nil && m.session.ConfigMode == utils.ConfigModeSimple {
		return -1
	}
	
	// Account for title and header (4 lines)
	// "Storage Configuration" + "\n\n" + "Configure storage..." + "\n\n"
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

func (m *StorageModel) clearAllFocus() {
	if m.storageDefaultClassSelect != nil {
		m.storageDefaultClassSelect.Blur()
	}
	if m.localPathEnabledToggle != nil {
		m.localPathEnabledToggle.Blur()
	}
	if m.longhornEnabledToggle != nil {
		m.longhornEnabledToggle.Blur()
	}
	if m.longhornNamespaceInput != nil {
		m.longhornNamespaceInput.Blur()
	}
	if m.longhornReplicaCountInput != nil {
		m.longhornReplicaCountInput.Blur()
	}
	if m.longhornStorageClassInput != nil {
		m.longhornStorageClassInput.Blur()
	}
	if m.longhornReclaimPolicySelect != nil {
		m.longhornReclaimPolicySelect.Blur()
	}
	if m.longhornBackupTargetInput != nil {
		m.longhornBackupTargetInput.Blur()
	}
	if m.longhornDataPathInput != nil {
		m.longhornDataPathInput.Blur()
	}
	if m.nfsEnabledToggle != nil {
		m.nfsEnabledToggle.Blur()
	}
	if m.nfsNamespaceInput != nil {
		m.nfsNamespaceInput.Blur()
	}
	if m.nfsBackendStorageInput != nil {
		m.nfsBackendStorageInput.Blur()
	}
	if m.nfsStorageSizeInput != nil {
		m.nfsStorageSizeInput.Blur()
	}
	if m.nfsStorageClassInput != nil {
		m.nfsStorageClassInput.Blur()
	}
}

func (m *StorageModel) focusField(fieldName string) {
	switch fieldName {
	case "storageDefaultClass":
		if m.storageDefaultClassSelect != nil {
			m.storageDefaultClassSelect.Focus()
		}
	case "localPathEnabled":
		if m.localPathEnabledToggle != nil {
			m.localPathEnabledToggle.Focus()
		}
	case "longhornEnabled":
		if m.longhornEnabledToggle != nil {
			m.longhornEnabledToggle.Focus()
		}
	case "longhornNamespace":
		if m.longhornNamespaceInput != nil {
			m.longhornNamespaceInput.Focus()
		}
	case "longhornReplicaCount":
		if m.longhornReplicaCountInput != nil {
			m.longhornReplicaCountInput.Focus()
		}
	case "longhornStorageClass":
		if m.longhornStorageClassInput != nil {
			m.longhornStorageClassInput.Focus()
		}
	case "longhornReclaimPolicy":
		if m.longhornReclaimPolicySelect != nil {
			m.longhornReclaimPolicySelect.Focus()
		}
	case "longhornBackupTarget":
		if m.longhornBackupTargetInput != nil {
			m.longhornBackupTargetInput.Focus()
		}
	case "longhornDataPath":
		if m.longhornDataPathInput != nil {
			m.longhornDataPathInput.Focus()
		}
	case "nfsEnabled":
		if m.nfsEnabledToggle != nil {
			m.nfsEnabledToggle.Focus()
		}
	case "nfsNamespace":
		if m.nfsNamespaceInput != nil {
			m.nfsNamespaceInput.Focus()
		}
	case "nfsBackendStorage":
		if m.nfsBackendStorageInput != nil {
			m.nfsBackendStorageInput.Focus()
		}
	case "nfsStorageSize":
		if m.nfsStorageSizeInput != nil {
			m.nfsStorageSizeInput.Focus()
		}
	case "nfsStorageClass":
		if m.nfsStorageClassInput != nil {
			m.nfsStorageClassInput.Focus()
		}
	}
}

func (m *StorageModel) nextField() {
	if len(m.fields) > 0 && m.focusedField < len(m.fields)-1 {
		m.focusedField++
		m.setFocus()
	}
}

func (m *StorageModel) prevField() {
	if m.focusedField > 0 {
		m.focusedField--
		m.setFocus()
	}
}

func (m *StorageModel) updateFocusedField(msg tea.Msg) tea.Cmd {
	if len(m.fields) == 0 || m.focusedField >= len(m.fields) {
		return nil
	}
	
	fieldToUpdate := m.fields[m.focusedField]
	switch fieldToUpdate {
	case "storageDefaultClass":
		if m.storageDefaultClassSelect != nil {
			return m.storageDefaultClassSelect.Update(msg)
		}
	case "localPathEnabled":
		if m.localPathEnabledToggle != nil {
			return m.localPathEnabledToggle.Update(msg)
		}
	case "longhornEnabled":
		if m.longhornEnabledToggle != nil {
			return m.longhornEnabledToggle.Update(msg)
		}
	case "longhornNamespace":
		if m.longhornNamespaceInput != nil {
			return m.longhornNamespaceInput.Update(msg)
		}
	case "longhornReplicaCount":
		if m.longhornReplicaCountInput != nil {
			return m.longhornReplicaCountInput.Update(msg)
		}
	case "longhornStorageClass":
		if m.longhornStorageClassInput != nil {
			return m.longhornStorageClassInput.Update(msg)
		}
	case "longhornReclaimPolicy":
		if m.longhornReclaimPolicySelect != nil {
			return m.longhornReclaimPolicySelect.Update(msg)
		}
	case "longhornBackupTarget":
		if m.longhornBackupTargetInput != nil {
			return m.longhornBackupTargetInput.Update(msg)
		}
	case "longhornDataPath":
		if m.longhornDataPathInput != nil {
			return m.longhornDataPathInput.Update(msg)
		}
	case "nfsEnabled":
		if m.nfsEnabledToggle != nil {
			return m.nfsEnabledToggle.Update(msg)
		}
	case "nfsNamespace":
		if m.nfsNamespaceInput != nil {
			return m.nfsNamespaceInput.Update(msg)
		}
	case "nfsBackendStorage":
		if m.nfsBackendStorageInput != nil {
			return m.nfsBackendStorageInput.Update(msg)
		}
	case "nfsStorageSize":
		if m.nfsStorageSizeInput != nil {
			return m.nfsStorageSizeInput.Update(msg)
		}
	case "nfsStorageClass":
		if m.nfsStorageClassInput != nil {
			return m.nfsStorageClassInput.Update(msg)
		}
	}
	return nil
}