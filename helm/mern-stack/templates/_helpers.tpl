{{/* Common labels applied to all resources */}}
{{- define "mern-stack.labels" -}}
app.kubernetes.io/part-of: mern-stack
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/* Build a full image reference from registry/repository:tag */}}
{{- define "mern-stack.image" -}}
{{- $root := index . 0 -}}
{{- $repo := index . 1 -}}
{{- printf "%s/%s:%s" $root.Values.image.registry $repo $root.Values.image.tag -}}
{{- end -}}
