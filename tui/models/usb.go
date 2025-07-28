package models

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"runtime"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"ztc-tui/colors"
	"ztc-tui/components"
	"ztc-tui/utils"
)

type USBModel struct {
	Width   int
	Height  int
	session *utils.Session

	// USB creation state
	devices       []USBDeviceInfo
	currentStep   int
	selected      int
	creating      bool
	progress      int
	scanning      bool
	currentDevice int

	// Animation state
	animationFrame int
	spinner        *components.Spinner

	// Error state
	scanError   error
	createError string

	// Node configuration
	nodeConfig []NodeConfig
}

type USBDeviceInfo struct {
	Device     string
	Size       string
	Label      string
	Mountpoint string
	Safe       bool
	Hostname   string
	IP         string
	Status     string // "pending", "creating", "complete", "error"
}

type NodeConfig struct {
	Hostname string
	IP       string
	Role     string
}

type USBInitMsg struct {
	Session *utils.Session
}

type USBScanCompleteMsg struct {
	Devices []USBDeviceInfo
	Err     error
}

type USBProgressMsg struct {
	Device   int
	Progress int
}

type USBScanTimeoutMsg struct{}

type USBSkipMsg struct{}

type USBAnimationMsg struct{}

type USBCreateErrorMsg struct {
	Device  int
	Error   error
	Message string
}

type USBCreationCompleteMsg struct{}

// lsblk JSON parsing structures (for Linux)
type LsblkOutput struct {
	BlockDevices []BlockDevice `json:"blockdevices"`
}

// diskutil JSON parsing structures (for macOS)
type DiskUtilOutput struct {
	AllDisksAndPartitions []DiskInfo `json:"AllDisksAndPartitions"`
}

type DiskInfo struct {
	DeviceIdentifier string `json:"DeviceIdentifier"`
	Size             int64  `json:"Size"`
	Content          string `json:"Content"`
	OSInternal       bool   `json:"OSInternal"`
	Partitions       []PartitionInfo `json:"Partitions"`
	VolumeName       string `json:"VolumeName"`
	MountPoint       string `json:"MountPoint"`
}

type PartitionInfo struct {
	DeviceIdentifier string `json:"DeviceIdentifier"`
	Size             int64  `json:"Size"`
	Content          string `json:"Content"`
	VolumeName       string `json:"VolumeName"`
	MountPoint       string `json:"MountPoint"`
}

type BlockDevice struct {
	Name       string        `json:"name"`
	Size       string        `json:"size"`
	Label      *string       `json:"label"`
	Mountpoint *string       `json:"mountpoint"`
	Type       string        `json:"type"`
	RM         bool          `json:"rm"`
	Children   []BlockDevice `json:"children,omitempty"`
}

// NewUSBModel creates a new USB model
func NewUSBModel() USBModel {
	// Default node configuration
	nodeConfig := []NodeConfig{
		{Hostname: "k3s-master", IP: "192.168.100.10", Role: "master"}
	}

	spinner := components.NewSpinner()
	spinner.Start()

	return USBModel{
		Width:          0, // Will be set by WindowSizeMsg
		Height:         0, // Will be set by WindowSizeMsg
		devices:        []USBDeviceInfo{}, // Will be populated by scanning
		currentStep:    0,
		selected:       0,
		creating:       false,
		progress:       0,
		scanning:       true,
		currentDevice:  0,
		animationFrame: 0,
		spinner:        spinner,
		scanError:      nil,
		createError:    "",
		nodeConfig:     nodeConfig,
	}
}

func (m USBModel) Init() tea.Cmd {
	return tea.Batch(
		m.scanUSBDevices(),
		func() tea.Msg {
			return components.SpinnerMsg{}
		},
	)
}

func (m USBModel) Update(msg tea.Msg) (USBModel, tea.Cmd) {
	var cmd tea.Cmd

	// Update spinner
	if m.spinner != nil {
		cmd = m.spinner.Update(msg)
	}

	switch msg := msg.(type) {
	case components.SpinnerMsg:
		// Handle spinner animation
		if m.scanning {
			return m, cmd
		}
		return m, nil

	case USBAnimationMsg:
		// Handle deprecated animation message for backward compatibility
		m.animationFrame = (m.animationFrame + 1) % 10
		// Continue animation only if still scanning
		if m.scanning {
			return m, m.startAnimation()
		}
		return m, nil

	case USBInitMsg:
		m.session = msg.Session
		// Load node configuration from session if available
		if config, err := m.session.LoadClusterConfig(); err == nil {
			m.nodeConfig = m.extractNodeConfig(config)
		}
		return m, nil

	case USBScanCompleteMsg:
		m.scanning = false
		if msg.Err != nil {
			m.scanError = msg.Err
			m.devices = []USBDeviceInfo{}
		} else {
			m.scanError = nil
			m.devices = msg.Devices
		}
		// Stop spinner when scan is complete
		if m.spinner != nil {
			m.spinner.Stop()
		}
		// Assign nodes to devices
		m.assignNodesToDevices()
		return m, nil

	case USBProgressMsg:
		m.currentDevice = msg.Device
		m.progress = msg.Progress
		if m.progress >= 100 {
			// All devices created, proceed to deployment
			// Update session state and save
			if m.session != nil {
				m.session.SetPhase("deploy")
				m.session.AddCompletedStep("usb")
				if err := m.session.Save(); err != nil {
					m.createError = fmt.Sprintf("Failed to save session: %v", err)
					return m, nil
				}
			}
			return m, func() tea.Msg {
				return StateTransitionMsg{To: "deploy"}
			}
		}
		return m, nil

	case USBScanTimeoutMsg:
		m.scanning = false
		m.devices = []USBDeviceInfo{}
		return m, nil

	case USBSkipMsg:
		// Skip USB creation and proceed to deployment
		// Update session state and save
		if m.session != nil {
			m.session.SetPhase("deploy")
			m.session.AddCompletedStep("usb-skipped")
			if err := m.session.Save(); err != nil {
				m.createError = fmt.Sprintf("Failed to save session: %v", err)
				return m, nil
			}
		}
		return m, func() tea.Msg {
			return StateTransitionMsg{To: "deploy"}
		}

	case USBCreateErrorMsg:
		// Handle USB creation error
		m.creating = false
		m.createError = msg.Message
		// Mark the device as failed
		if msg.Device < len(m.devices) {
			m.devices[msg.Device].Status = "error"
		}
		return m, nil

	case USBCreationCompleteMsg:
		// USB creation completed successfully
		m.creating = false
		m.createError = ""
		// Mark all devices as complete
		for i := range m.devices {
			if m.devices[i].Status == "pending" {
				m.devices[i].Status = "complete"
			}
		}
		return m, nil

	case tea.KeyMsg:
		if m.scanning {
			// Only allow quit/escape during scanning
			switch msg.String() {
			case "q", "ctrl+c":
				return m, func() tea.Msg {
					return StateTransitionMsg{To: "quit"}
				}
			case "esc":
				return m, func() tea.Msg {
					return StateTransitionMsg{To: "config"}
				}
			}
			return m, nil
		}

		switch msg.String() {
		case "enter":
			if !m.creating && len(m.devices) > 0 {
				// Start USB creation
				m.creating = true
				m.createError = "" // Clear any previous error
				return m, m.createUSBDrives()
			}
		case "up", "k":
			if !m.creating && m.selected > 0 {
				m.selected--
			}
		case "down", "j":
			if !m.creating && m.selected < len(m.devices)-1 {
				m.selected++
			}
		case "r":
			// Rescan USB devices OR retry USB creation if there was an error
			if m.createError != "" {
				// Retry USB creation
				m.creating = true
				m.createError = ""
				// Reset all devices to pending status
				for i := range m.devices {
					if m.devices[i].Status == "error" {
						m.devices[i].Status = "pending"
					}
				}
				return m, m.createUSBDrives()
			} else {
				// Rescan USB devices
				m.scanning = true
				m.devices = []USBDeviceInfo{}
				m.scanError = nil
				m.createError = ""
				// Restart spinner
				if m.spinner != nil {
					m.spinner.Start()
				}
				return m, tea.Batch(m.scanUSBDevices(), func() tea.Msg {
					return components.SpinnerMsg{}
				})
			}
		case "s":
			// Skip USB creation and proceed to deployment
			return m, func() tea.Msg {
				return USBSkipMsg{}
			}
		case "q", "ctrl+c":
			return m, func() tea.Msg {
				return StateTransitionMsg{To: "quit"}
			}
		case "esc":
			return m, func() tea.Msg {
				return StateTransitionMsg{To: "config"}
			}
		}
	}

	return m, nil
}

func (m USBModel) View() string {
	var content strings.Builder

	// Title
	title := lipgloss.NewStyle().
		Foreground(colors.ZtcOrange).
		Bold(true).
		Render("USB Drive Creation")

	content.WriteString(title + "\n\n")

	// Handle different states
	if m.scanning {
		// Scanning state
		content.WriteString("Scanning for USB devices...\n\n")

		// Use unified spinner or fallback to animation frame
		var spinnerChar string
		if m.spinner != nil {
			spinnerChar = m.spinner.View()
		} else {
			// Fallback to deprecated animation frame
			spinner := []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
			spinnerChar = spinner[m.animationFrame%len(spinner)]
		}

		scanText := lipgloss.NewStyle().
			Foreground(colors.ZtcOrange).
			Render(spinnerChar + " Detecting USB devices...")

		content.WriteString(scanText + "\n\n")
		content.WriteString("This may take a few seconds...\n")

	} else if !m.creating {
		// Device selection state
		instructions := `Create bootable USB drives for your cluster nodes.
Each node will need its own USB drive for automated installation.

Detected USB devices:`
		content.WriteString(instructions + "\n\n")

		if m.scanError != nil {
			// Show scan error
			errorText := lipgloss.NewStyle().
				Foreground(colors.ZtcDarkOrange).
				Render("✗ USB scan failed: " + m.scanError.Error())
			content.WriteString(errorText + "\n\n")
			content.WriteString("Options:\n")
			content.WriteString("• Press 'r' to try scanning again\n")
			content.WriteString("• Press 's' to skip USB creation and proceed with deployment\n")
			content.WriteString("• Press 'Esc' to go back to configuration\n\n")

			skipText := lipgloss.NewStyle().
				Foreground(colors.ZtcOrange).
				Render("Note: Skipping USB creation means you'll need to manually provision nodes")
			content.WriteString(skipText + "\n")
		} else if len(m.devices) == 0 {
			noDevicesText := lipgloss.NewStyle().
				Foreground(colors.ZtcDarkOrange).
				Render("⚠ No USB devices detected")
			content.WriteString(noDevicesText + "\n\n")
			content.WriteString("Options:\n")
			content.WriteString("• Insert USB drives and press 'r' to rescan\n")
			content.WriteString("• Press 's' to skip USB creation and proceed with deployment\n")
			content.WriteString("• Press 'Esc' to go back to configuration\n\n")

			skipText := lipgloss.NewStyle().
				Foreground(colors.ZtcOrange).
				Render("Note: Skipping USB creation means you'll need to manually provision nodes")
			content.WriteString(skipText + "\n")
		} else {
			// Device list
			for i, device := range m.devices {
				style := lipgloss.NewStyle().
					Padding(0, 1)

				if i == m.selected {
					style = style.
						Background(colors.ZtcOrange).
						Foreground(colors.ZtcBlack)
				} else {
					style = style.
						Foreground(colors.ZtcWhite)
				}

				deviceInfo := fmt.Sprintf("%s (%s) → %s (%s)",
					device.Device, device.Size, device.Hostname, device.IP)

				content.WriteString(style.Render(deviceInfo) + "\n")
			}

			content.WriteString("\nPress Enter to create USB drives")
		}

	} else {
		// Creation progress state
		content.WriteString("Creating USB drives...\n\n")

		for _, device := range m.devices {
			status := m.renderDeviceStatus(device)
			content.WriteString(fmt.Sprintf("%s %s → %s\n",
				status, device.Device, device.Hostname))
		}

		// Progress bar
		progress := m.renderProgressBar()
		content.WriteString("\n" + progress + "\n")

		if m.progress >= 100 {
			successText := lipgloss.NewStyle().
				Foreground(colors.ZtcOrange).
				Render("✓ All USB drives created successfully!")

			content.WriteString("\n" + successText)
			content.WriteString("\nPress Enter to continue to deployment")
		}

		// Show creation error if present
		if m.createError != "" {
			// Show creation error
			errorText := lipgloss.NewStyle().
				Foreground(colors.ZtcDarkOrange).
				Bold(true).
				Render("✗ USB Creation Error")
			content.WriteString("\n\n" + errorText + "\n\n")

			errorDetails := lipgloss.NewStyle().
				Foreground(colors.ZtcDarkOrange).
				Render(m.createError)
			content.WriteString(errorDetails + "\n\n")

			content.WriteString("Options:\n")
			content.WriteString("• Press 'r' to try again\n")
			content.WriteString("• Press 's' to skip USB creation and proceed with deployment\n")
			content.WriteString("• Press 'Esc' to go back to configuration\n")
		}
	}

	// Help text
	helpText := ""
	if m.scanning {
		helpText = "Scanning... • Esc Back • q Quit"
	} else if !m.creating {
		if len(m.devices) > 0 {
			helpText = "↑↓ Navigate • Enter Create • r Rescan • s Skip • Esc Back • q Quit"
		} else {
			helpText = "r Rescan • s Skip • Esc Back • q Quit"
		}
	} else if m.createError != "" {
		helpText = "r Retry • s Skip • Esc Back • q Quit"
	} else {
		helpText = "Creating USB drives... • q Quit"
	}

	help := lipgloss.NewStyle().
		Foreground(colors.ZtcLightGray).
		Render(helpText)

	content.WriteString("\n\n" + help)

	return content.String()
}

func (m USBModel) renderDeviceStatus(device USBDeviceInfo) string {
	switch device.Status {
	case "pending":
		return lipgloss.NewStyle().Foreground(colors.ZtcLightGray).Render("○")
	case "creating":
		return lipgloss.NewStyle().Foreground(colors.ZtcOrange).Render("◐")
	case "complete":
		return lipgloss.NewStyle().Foreground(colors.ZtcOrange).Render("●")
	case "error":
		return lipgloss.NewStyle().Foreground(colors.ZtcDarkOrange).Render("✗")
	default:
		return "?"
	}
}

func (m USBModel) renderProgressBar() string {
	width := 50
	filled := int(float64(width) * (float64(m.progress) / 100.0))

	bar := strings.Repeat("█", filled) + strings.Repeat("░", width-filled)

	return fmt.Sprintf("[%s] %d%%", bar, m.progress)
}

// Helper methods
func (m USBModel) extractNodeConfig(config *utils.ClusterConfig) []NodeConfig {
	var nodes []NodeConfig

	// Extract cluster nodes
	for hostname, node := range config.Nodes.ClusterNodes {
		nodes = append(nodes, NodeConfig{
			Hostname: hostname,
			IP:       node.IP,
			Role:     node.Role,
		})
	}

	return nodes
}

func (m *USBModel) assignNodesToDevices() {
	// Assign nodes to detected devices
	for i := range m.devices {
		if i < len(m.nodeConfig) {
			m.devices[i].Hostname = m.nodeConfig[i].Hostname
			m.devices[i].IP = m.nodeConfig[i].IP
		}
	}
}

func (m USBModel) scanUSBDevices() tea.Cmd {
	return func() tea.Msg {
		// Detect actual USB devices using lsblk
		devices, err := detectUSBDevices()
		if err != nil {
			// Return error to be displayed to user
			return USBScanCompleteMsg{Devices: []USBDeviceInfo{}, Err: err}
		}

		return USBScanCompleteMsg{Devices: devices, Err: nil}
	}
}

// detectUSBDevices dispatches to the correct OS-specific function.
func detectUSBDevices() ([]USBDeviceInfo, error) {
	switch runtime.GOOS {
	case "linux":
		return detectUSBDevicesLinux()
	case "darwin":
		return detectUSBDevicesDarwin()
	default:
		return nil, fmt.Errorf("unsupported operating system: %s", runtime.GOOS)
	}
}

// detectUSBDevicesLinux uses lsblk to detect actual USB devices on Linux.
func detectUSBDevicesLinux() ([]USBDeviceInfo, error) {
	// Execute lsblk command to get device information
	cmd := exec.Command("lsblk", "-o", "NAME,SIZE,LABEL,MOUNTPOINT,TYPE,RM", "-J")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to execute lsblk: %w", err)
	}

	// Parse JSON output
	var lsblkOutput LsblkOutput
	if err := json.Unmarshal(output, &lsblkOutput); err != nil {
		return nil, fmt.Errorf("failed to parse lsblk output: %w", err)
	}

	// Filter for removable disk devices (USB drives)
	var devices []USBDeviceInfo
	for _, device := range lsblkOutput.BlockDevices {
		if device.Type == "disk" && device.RM {
			// Convert lsblk device to USBDeviceInfo
			usbDevice := USBDeviceInfo{
				Device:     "/dev/" + device.Name,
				Size:       device.Size,
				Label:      getStringOrEmpty(device.Label),
				Mountpoint: getStringOrEmpty(device.Mountpoint),
				Safe:       isSafeDeviceLinux(device),
				Status:     "pending",
			}
			devices = append(devices, usbDevice)
		}
	}

	return devices, nil
}

// detectUSBDevicesDarwin uses diskutil to detect actual USB devices on macOS.
func detectUSBDevicesDarwin() ([]USBDeviceInfo, error) {
	cmd := exec.Command("diskutil", "list", "-json")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to execute diskutil: %w", err)
	}

	var diskutilOutput DiskUtilOutput
	if err := json.Unmarshal(output, &diskutilOutput); err != nil {
		return nil, fmt.Errorf("failed to parse diskutil output: %w", err)
	}

	var devices []USBDeviceInfo
	for _, disk := range diskutilOutput.AllDisksAndPartitions {
		// Filter for physical, external disks
		if !disk.OSInternal {
			devices = append(devices, USBDeviceInfo{
				Device:     "/dev/" + disk.DeviceIdentifier,
				Size:       fmt.Sprintf("%dG", disk.Size/1000/1000/1000),
				Label:      disk.VolumeName,
				Mountpoint: disk.MountPoint,
				Safe:       true, // Assume external disks are safe for now
				Status:     "pending",
			})
		}
	}

	return devices, nil
}

// getStringOrEmpty safely converts a string pointer to string
func getStringOrEmpty(ptr *string) string {
	if ptr == nil {
		return ""
	}
	return *ptr
}

// isSafeDeviceLinux checks if a device is safe to use (not a system drive) on Linux.
func isSafeDeviceLinux(device BlockDevice) bool {
	// Basic safety checks - avoid devices that are likely system drives

	// Check if device is mounted to critical system paths
	if device.Mountpoint != nil {
		mountpoint := *device.Mountpoint
		systemPaths := []string{"/", "/boot", "/usr", "/var", "/home"}
		for _, path := range systemPaths {
			if strings.HasPrefix(mountpoint, path) {
				return false
			}
		}
	}

	// Check children for system mountpoints
	for _, child := range device.Children {
		if !isSafeDeviceLinux(child) {
			return false
		}
	}

	// If device is removable and doesn't have system mountpoints, it's likely safe
	return device.RM
}

// startAnimation creates a command to animate the spinner (deprecated - kept for backward compatibility)
func (m USBModel) startAnimation() tea.Cmd {
	return tea.Tick(time.Millisecond*100, func(t time.Time) tea.Msg {
		return USBAnimationMsg{}
	})
}

func (m USBModel) createUSBDrives() tea.Cmd {
	return func() tea.Msg {
		// Create USB drives for each configured device
		for deviceIndex, device := range m.devices {
			if device.Status == "pending" && device.Hostname != "" {
				// Create USB drive for this device
				if err := createUSBDrive(device); err != nil {
					return USBCreateErrorMsg{
						Device:  deviceIndex,
						Error:   err,
						Message: fmt.Sprintf("Failed to create USB for %s: %v", device.Hostname, err),
					}
				}

				// Send progress update for successful creation
				// In a real implementation, this would be sent periodically during creation
				return USBProgressMsg{Device: deviceIndex, Progress: 100}
			}
		}

		// All devices processed successfully
		return USBCreationCompleteMsg{}
	}
}

// createUSBDrive creates a USB drive for a specific device
func createUSBDrive(device USBDeviceInfo) error {
	// Safety check - ensure device is safe to use
	if !device.Safe {
		return fmt.Errorf("device %s is not safe to use", device.Device)
	}

	// Check if device is still available
	if !isDeviceAvailable(device.Device) {
		return fmt.Errorf("device %s is no longer available", device.Device)
	}

	// Execute USB creation script (this would be the actual implementation)
	// For now, simulate the creation process
	cmd := exec.Command("scripts/tui/create-usb.sh", device.Device, device.Hostname, extractIPOctet(device.IP))

	// Capture both stdout and stderr for detailed error reporting
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("USB creation failed: %w\nOutput: %s", err, string(output))
	}

	return nil
}

// isDeviceAvailable checks if a USB device is still available
func isDeviceAvailable(devicePath string) bool {
	devices, err := detectUSBDevices()
	if err != nil {
		return false
	}

	for _, device := range devices {
		if device.Device == devicePath {
			return true
		}
	}
	return false
}

// extractIPOctet extracts the last octet from an IP address
func extractIPOctet(ip string) string {
	parts := strings.Split(ip, ".")
	if len(parts) == 4 {
		return parts[3]
	}
	return "10" // Default fallback
}
