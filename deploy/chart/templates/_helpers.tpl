{{- define "demo.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "demo.labels" -}}
{{ include "demo.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end }}

{{- /*
repo:tag@digest - the tag is informational, the digest is what the runtime pulls.
The chart allows a tag-only reference (used by the CI e2e cluster); admission
policy is what requires the digest in real environments.
*/}}
{{- define "demo.image" -}}
{{ .Values.image.repository }}:{{ required "image.tag is required" .Values.image.tag }}{{ with .Values.image.digest }}@{{ . }}{{ end }}
{{- end }}
