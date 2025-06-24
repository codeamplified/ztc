{{/*
Homelab Storage Chart Helpers
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "homelab-storage.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "homelab-storage.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "homelab-storage.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "homelab-storage.labels" -}}
helm.sh/chart: {{ include "homelab-storage.chart" . }}
{{ include "homelab-storage.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "homelab-storage.selectorLabels" -}}
app.kubernetes.io/name: {{ include "homelab-storage.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
NFS Provisioner labels
*/}}
{{- define "homelab-storage.nfs.labels" -}}
{{ include "homelab-storage.labels" . }}
app.kubernetes.io/component: nfs-provisioner
{{- end }}

{{/*
NFS Provisioner selector labels
*/}}
{{- define "homelab-storage.nfs.selectorLabels" -}}
{{ include "homelab-storage.selectorLabels" . }}
app.kubernetes.io/component: nfs-provisioner
{{- end }}