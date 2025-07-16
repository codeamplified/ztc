package utils

import (
	"fmt"
	"os"
	"path/filepath"
	"time"

	"gopkg.in/yaml.v3"
)

// Session represents the persistent state of the TUI wizard
type Session struct {
	ID             string            `yaml:"id"`
	StartedAt      time.Time         `yaml:"started_at"`
	CurrentPhase   string            `yaml:"current_phase"`
	CompletedSteps []string          `yaml:"completed_steps"`
	ClusterConfig  string            `yaml:"cluster_config"`
	USBDevices     []USBDevice       `yaml:"usb_devices"`
	DeploymentLog  string            `yaml:"deployment_log"`
	Progress       map[string]int    `yaml:"progress"`
	Metadata       map[string]string `yaml:"metadata"`
}

// USBDevice represents a USB device used for node installation
type USBDevice struct {
	Device     string `yaml:"device"`
	Hostname   string `yaml:"hostname"`
	IP         string `yaml:"ip"`
	Created    bool   `yaml:"created"`
	Verified   bool   `yaml:"verified"`
	CreatedAt  time.Time `yaml:"created_at"`
}

// ClusterConfig represents the cluster configuration
type ClusterConfig struct {
	Cluster    ClusterMetadata   `yaml:"cluster" json:"cluster"`
	Network    NetworkConfig     `yaml:"network" json:"network"`
	Nodes      NodesConfig       `yaml:"nodes" json:"nodes"`
	Storage    StorageConfig     `yaml:"storage" json:"storage"`
	Components ComponentsConfig  `yaml:"components" json:"components"`
	Workloads  WorkloadsConfig   `yaml:"workloads" json:"workloads"`
}

// ClusterMetadata represents the cluster metadata section
type ClusterMetadata struct {
	Name        string     `yaml:"name" json:"name"`
	Description string     `yaml:"description" json:"description"`
	Version     string     `yaml:"version" json:"version"`
	HAConfig    *HAConfig  `yaml:"ha_config,omitempty" json:"ha_config,omitempty"`
}

// HAConfig represents high availability configuration
type HAConfig struct {
	Enabled      bool          `yaml:"enabled" json:"enabled"`
	VirtualIP    string        `yaml:"virtual_ip,omitempty" json:"virtual_ip,omitempty"`
	LoadBalancer *LoadBalancer `yaml:"load_balancer,omitempty" json:"load_balancer,omitempty"`
}

// LoadBalancer represents load balancer configuration
type LoadBalancer struct {
	Type string `yaml:"type" json:"type"`
	Port int    `yaml:"port,omitempty" json:"port,omitempty"`
}

type NetworkConfig struct {
	Subnet string    `yaml:"subnet" json:"subnet"`
	DNS    DNSConfig `yaml:"dns" json:"dns"`
}

type DNSConfig struct {
	Enabled   bool     `yaml:"enabled" json:"enabled"`
	ServerIP  string   `yaml:"server_ip" json:"server_ip"`
	Domain    string   `yaml:"domain" json:"domain"`
	Upstreams []string `yaml:"upstreams" json:"upstreams"`
}

type NodesConfig struct {
	SSH          SSHConfig               `yaml:"ssh" json:"ssh"`
	ClusterNodes map[string]ClusterNode  `yaml:"cluster_nodes" json:"cluster_nodes"`
	StorageNode  map[string]StorageNode  `yaml:"storage_node,omitempty" json:"storage_node,omitempty"`
}

type SSHConfig struct {
	KeyPath  string `yaml:"key_path" json:"key_path"`
	Username string `yaml:"username" json:"username"`
}

type ClusterNode struct {
	IP        string            `yaml:"ip" json:"ip"`
	Role      string            `yaml:"role" json:"role"`
	Resources NodeResources     `yaml:"resources,omitempty" json:"resources,omitempty"`
}

type StorageNode struct {
	IP        string            `yaml:"ip" json:"ip"`
	Role      string            `yaml:"role" json:"role"`
	Resources StorageResources  `yaml:"resources,omitempty" json:"resources,omitempty"`
}

type NodeResources struct {
	CPU    string `yaml:"cpu" json:"cpu"`
	Memory string `yaml:"memory" json:"memory"`
}

type StorageResources struct {
	CPU     string `yaml:"cpu" json:"cpu"`
	Memory  string `yaml:"memory" json:"memory"`
	Storage string `yaml:"storage" json:"storage"`
}

type StorageConfig struct {
	Strategy     string                 `yaml:"strategy" json:"strategy"`
	DefaultClass string                 `yaml:"default_class" json:"default_class"`
	LocalPath    LocalPathConfig        `yaml:"local_path" json:"local_path"`
	NFS          NFSConfig              `yaml:"nfs" json:"nfs"`
	Longhorn     LonghornConfig         `yaml:"longhorn" json:"longhorn"`
}

type LocalPathConfig struct {
	Enabled   bool `yaml:"enabled" json:"enabled"`
	IsDefault bool `yaml:"is_default" json:"is_default"`
}

type NFSConfig struct {
	Enabled      bool               `yaml:"enabled" json:"enabled"`
	Server       *NFSServerConfig   `yaml:"server,omitempty" json:"server,omitempty"`
	StorageClass *NFSStorageClass   `yaml:"storage_class,omitempty" json:"storage_class,omitempty"`
}

type NFSServerConfig struct {
	IP   string `yaml:"ip" json:"ip"`
	Path string `yaml:"path" json:"path"`
}

type NFSStorageClass struct {
	Name          string `yaml:"name" json:"name"`
	IsDefault     bool   `yaml:"is_default" json:"is_default"`
	ReclaimPolicy string `yaml:"reclaim_policy" json:"reclaim_policy"`
}

type LonghornConfig struct {
	Enabled bool `yaml:"enabled" json:"enabled"`
}

type ComponentsConfig struct {
	SealedSecrets SealedSecretsConfig `yaml:"sealed_secrets" json:"sealed_secrets"`
	ArgoCD        ArgoCDConfig        `yaml:"argocd" json:"argocd"`
	Monitoring    MonitoringConfig    `yaml:"monitoring" json:"monitoring"`
	Gitea         GiteaConfig         `yaml:"gitea" json:"gitea"`
	Homepage      HomepageConfig      `yaml:"homepage" json:"homepage"`
}

type SealedSecretsConfig struct {
	Enabled bool `yaml:"enabled" json:"enabled"`
}

type ArgoCDConfig struct {
	Enabled   bool   `yaml:"enabled" json:"enabled"`
	Namespace string `yaml:"namespace" json:"namespace"`
}

type MonitoringConfig struct {
	Enabled   bool   `yaml:"enabled" json:"enabled"`
	Namespace string `yaml:"namespace" json:"namespace"`
}

type GiteaConfig struct {
	Enabled   bool   `yaml:"enabled" json:"enabled"`
	Namespace string `yaml:"namespace" json:"namespace"`
}

type HomepageConfig struct {
	Enabled   bool   `yaml:"enabled" json:"enabled"`
	Namespace string `yaml:"namespace" json:"namespace"`
}

type WorkloadsConfig struct {
	AutoDeployBundles []string `yaml:"auto_deploy_bundles" json:"auto_deploy_bundles"`
}

const sessionFile = ".ztc-session.yaml"

// NewSession creates a new session with default values
func NewSession() *Session {
	return &Session{
		ID:             generateSessionID(),
		StartedAt:      time.Now(),
		CurrentPhase:   "welcome",
		CompletedSteps: []string{},
		ClusterConfig:  "cluster.yaml",
		USBDevices:     []USBDevice{},
		DeploymentLog:  "",
		Progress:       make(map[string]int),
		Metadata:       make(map[string]string),
	}
}

// LoadSession loads session from file or creates a new one
func LoadSession() (*Session, error) {
	if _, err := os.Stat(sessionFile); os.IsNotExist(err) {
		return NewSession(), nil
	}

	data, err := os.ReadFile(sessionFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read session file: %w", err)
	}

	var session Session
	if err := yaml.Unmarshal(data, &session); err != nil {
		return nil, fmt.Errorf("failed to unmarshal session: %w", err)
	}

	return &session, nil
}

// Save saves the session to file
func (s *Session) Save() error {
	data, err := yaml.Marshal(s)
	if err != nil {
		return fmt.Errorf("failed to marshal session: %w", err)
	}

	if err := os.WriteFile(sessionFile, data, 0644); err != nil {
		return fmt.Errorf("failed to write session file: %w", err)
	}

	return nil
}

// SetPhase sets the current phase and saves the session
func (s *Session) SetPhase(phase string) error {
	s.CurrentPhase = phase
	return s.Save()
}

// AddCompletedStep adds a step to the completed steps
func (s *Session) AddCompletedStep(step string) error {
	for _, existing := range s.CompletedSteps {
		if existing == step {
			return nil // Already completed
		}
	}
	s.CompletedSteps = append(s.CompletedSteps, step)
	return s.Save()
}

// IsStepCompleted checks if a step is completed
func (s *Session) IsStepCompleted(step string) bool {
	for _, completed := range s.CompletedSteps {
		if completed == step {
			return true
		}
	}
	return false
}

// AddUSBDevice adds a USB device to the session
func (s *Session) AddUSBDevice(device USBDevice) error {
	s.USBDevices = append(s.USBDevices, device)
	return s.Save()
}

// SetProgress sets progress for a specific task
func (s *Session) SetProgress(task string, progress int) error {
	s.Progress[task] = progress
	return s.Save()
}

// GetProgress gets progress for a specific task
func (s *Session) GetProgress(task string) int {
	return s.Progress[task]
}

// SetMetadata sets metadata key-value pair
func (s *Session) SetMetadata(key, value string) error {
	s.Metadata[key] = value
	return s.Save()
}

// GetMetadata gets metadata value by key
func (s *Session) GetMetadata(key string) string {
	return s.Metadata[key]
}

// LoadClusterConfig loads the cluster configuration from file
func (s *Session) LoadClusterConfig() (*ClusterConfig, error) {
	if _, err := os.Stat(s.ClusterConfig); os.IsNotExist(err) {
		return nil, fmt.Errorf("cluster config file not found: %s", s.ClusterConfig)
	}

	data, err := os.ReadFile(s.ClusterConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to read cluster config: %w", err)
	}

	var config ClusterConfig
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to unmarshal cluster config: %w", err)
	}

	// Validate configuration against schema
	if validationResult, err := GetValidator().ValidateClusterConfig(&config); err != nil {
		return nil, fmt.Errorf("failed to validate cluster config: %w", err)
	} else if !validationResult.Valid {
		return nil, fmt.Errorf("cluster config validation failed:\n%s", validationResult.FormatErrors())
	}

	return &config, nil
}

// SaveClusterConfig saves the cluster configuration to file
func (s *Session) SaveClusterConfig(config *ClusterConfig) error {
	data, err := yaml.Marshal(config)
	if err != nil {
		return fmt.Errorf("failed to marshal cluster config: %w", err)
	}

	// Add YAML schema header
	header := "# yaml-language-server: $schema=./schema/cluster-schema.json\n"
	header += "# Zero Touch Cluster Configuration\n"
	header += fmt.Sprintf("# Generated by TUI wizard on %s\n\n", time.Now().Format(time.RFC3339))

	content := header + string(data)

	if err := os.WriteFile(s.ClusterConfig, []byte(content), 0644); err != nil {
		return fmt.Errorf("failed to write cluster config: %w", err)
	}

	return nil
}

// Clean removes the session file
func (s *Session) Clean() error {
	if err := os.Remove(sessionFile); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to remove session file: %w", err)
	}
	return nil
}

// generateSessionID generates a simple session ID
func generateSessionID() string {
	return fmt.Sprintf("ztc-%d", time.Now().Unix())
}

// GetWorkspaceDir returns the workspace directory
func GetWorkspaceDir() string {
	if wd := os.Getenv("ZTC_WORKSPACE"); wd != "" {
		return wd
	}
	wd, _ := os.Getwd()
	return wd
}

// GetLogFile returns the path to the deployment log file
func GetLogFile() string {
	return filepath.Join(GetWorkspaceDir(), ".ztc-deployment.log")
}

// GetStatusFile returns the path to the deployment status file
func GetStatusFile() string {
	return filepath.Join(GetWorkspaceDir(), ".ztc-status.json")
}

// Mission represents the user's chosen cluster type
type Mission string

const (
	MissionPioneer     Mission = "pioneer"
	MissionHomesteader Mission = "homesteader"
)

// Template represents a cluster template with metadata
type Template struct {
	Name         string   `yaml:"name"`
	Description  string   `yaml:"description"`
	Mission      Mission  `yaml:"mission"`
	NodeCount    string   `yaml:"node_count"`
	HardwareReq  string   `yaml:"hardware_req"`
	Bundles      []string `yaml:"bundles"`
	Config       *ClusterConfig `yaml:"config"`
}

// LoadClusterTemplate loads a cluster template based on mission
func LoadClusterTemplate(mission Mission) (*ClusterConfig, error) {
	templatePath := filepath.Join(GetWorkspaceDir(), "templates", fmt.Sprintf("cluster-%s.yaml", string(mission)))
	
	// Check if template file exists
	if _, err := os.Stat(templatePath); os.IsNotExist(err) {
		return nil, fmt.Errorf("template not found for mission %s: %s", mission, templatePath)
	}

	// Read template file
	data, err := os.ReadFile(templatePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read template file: %w", err)
	}

	// Parse YAML
	var config ClusterConfig
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse template YAML: %w", err)
	}

	return &config, nil
}

// ValidateTemplate is now implemented in validation.go using JSON schema validation

// GetAvailableBundles returns available workload bundles for a mission
func GetAvailableBundles(mission Mission) []Bundle {
	switch mission {
	case MissionPioneer:
		return []Bundle{
			{
				ID:          "starter",
				Name:        "Starter Bundle",
				Description: "Essential homelab services: Homepage dashboard + Uptime Kuma monitoring",
				Services:    []string{"homepage", "uptime-kuma"},
				Resources:   "192Mi RAM, 2Gi storage",
				Recommended: true,
			},
		}
	case MissionHomesteader:
		return []Bundle{
			{
				ID:          "starter",
				Name:        "Starter Bundle",
				Description: "Essential homelab services",
				Services:    []string{"homepage", "uptime-kuma"},
				Resources:   "192Mi RAM, 2Gi storage",
				Recommended: true,
			},
			{
				ID:          "monitoring",
				Name:        "Monitoring Bundle", 
				Description: "Complete monitoring solution",
				Services:    []string{"uptime-kuma", "homepage"},
				Resources:   "192Mi RAM, 3Gi storage",
				Recommended: true,
			},
			{
				ID:          "productivity",
				Name:        "Productivity Bundle",
				Description: "Development and automation toolkit",
				Services:    []string{"code-server", "n8n"},
				Resources:   "1Gi RAM, 15Gi storage",
				Recommended: false,
			},
			{
				ID:          "security",
				Name:        "Security Bundle",
				Description: "Professional password management",
				Services:    []string{"vaultwarden"},
				Resources:   "128Mi RAM, 5Gi storage",
				Recommended: false,
			},
		}
	default:
		return []Bundle{}
	}
}

// Bundle represents a workload bundle
type Bundle struct {
	ID          string   `yaml:"id" json:"id"`
	Name        string   `yaml:"name" json:"name"`
	Description string   `yaml:"description" json:"description"`
	Services    []string `yaml:"services" json:"services"`
	Resources   string   `yaml:"resources" json:"resources"`
	Recommended bool     `yaml:"recommended" json:"recommended"`
}

// GetTemplateMetadata returns metadata about a template
func GetTemplateMetadata(mission Mission) (*TemplateMetadata, error) {
	switch mission {
	case MissionPioneer:
		return &TemplateMetadata{
			Mission:      MissionPioneer,
			Name:         "Pioneer Mission",
			Description:  "Explore Kubernetes with minimal gear (1-4 nodes)",
			NodeCount:    "1-4 nodes",
			HardwareReq:  "4GB RAM per node, 32GB storage minimum",
			Architecture: "Single master, converged services",
			StorageTypes: []string{"local-path"},
			UseCases:     []string{"Learning", "Experimentation", "Testing"},
			TradeOffs:    []string{"Single point of failure", "Limited scalability"},
		}, nil
	case MissionHomesteader:
		return &TemplateMetadata{
			Mission:      MissionHomesteader,
			Name:         "Homesteader Mission",
			Description:  "Build a permanent, reliable digital home (5+ nodes)",
			NodeCount:    "5+ nodes (3 masters, 2+ workers)",
			HardwareReq:  "8GB RAM per master, 4GB per worker, 100GB storage minimum",
			Architecture: "HA masters with VIP, dedicated storage",
			StorageTypes: []string{"local-path", "longhorn", "minio"},
			UseCases:     []string{"Production services", "High availability", "Data safety"},
			TradeOffs:    []string{"Higher resource requirements", "Increased complexity"},
		}, nil
	default:
		return nil, fmt.Errorf("unknown mission: %s", mission)
	}
}

// TemplateMetadata provides information about a template
type TemplateMetadata struct {
	Mission      Mission  `yaml:"mission" json:"mission"`
	Name         string   `yaml:"name" json:"name"`
	Description  string   `yaml:"description" json:"description"`
	NodeCount    string   `yaml:"node_count" json:"node_count"`
	HardwareReq  string   `yaml:"hardware_req" json:"hardware_req"`
	Architecture string   `yaml:"architecture" json:"architecture"`
	StorageTypes []string `yaml:"storage_types" json:"storage_types"`
	UseCases     []string `yaml:"use_cases" json:"use_cases"`
	TradeOffs    []string `yaml:"trade_offs" json:"trade_offs"`
}

// GetNodeList extracts node information from cluster config for USB creation
func GetNodeList(config *ClusterConfig) []NodeInfo {
	var nodes []NodeInfo
	
	// Add cluster nodes
	for hostname, node := range config.Nodes.ClusterNodes {
		nodes = append(nodes, NodeInfo{
			Hostname: hostname,
			IP:       node.IP,
			Role:     node.Role,
			Type:     "cluster",
		})
	}
	
	// Add storage nodes if present
	for hostname, node := range config.Nodes.StorageNode {
		nodes = append(nodes, NodeInfo{
			Hostname: hostname,
			IP:       node.IP,
			Role:     node.Role,
			Type:     "storage",
		})
	}
	
	return nodes
}

// NodeInfo represents node information for USB creation
type NodeInfo struct {
	Hostname string `yaml:"hostname" json:"hostname"`
	IP       string `yaml:"ip" json:"ip"`
	Role     string `yaml:"role" json:"role"`
	Type     string `yaml:"type" json:"type"` // "cluster" or "storage"
}