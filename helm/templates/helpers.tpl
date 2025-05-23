{{/*
Expand the name of the chart.
*/}}
{{- define "voting-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "voting-app.fullname" -}}
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
{{- define "voting-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "voting-app.labels" -}}
helm.sh/chart: {{ include "voting-app.chart" . }}
{{ include "voting-app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "voting-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "voting-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
DB labels
*/}}
{{- define "voting-app.db.labels" -}}
app: {{ .Values.db.name }}
{{- end }}

{{/*
Redis labels
*/}}
{{- define "voting-app.redis.labels" -}}
app: {{ .Values.redis.name }}
{{- end }}

{{/*
Vote labels
*/}}
{{- define "voting-app.vote.labels" -}}
app: {{ .Values.vote.name }}
{{- end }}

{{/*
Result labels
*/}}
{{- define "voting-app.result.labels" -}}
app: {{ .Values.result.name }}
{{- end }}

{{/*
Worker labels
*/}}
{{- define "voting-app.worker.labels" -}}
app: {{ .Values.worker.name }}
{{- end }}

{{/*
Worker Canary labels
*/}}
{{- define "voting-app.worker.canary.labels" -}}
app: {{ .Values.worker.name }}
version: canary
{{- end }}
