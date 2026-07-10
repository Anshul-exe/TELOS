{{/*
TELOS chart helpers.
*/}}

{{/*
Namespace used by every resource. Single source of truth = .Values.global.namespace.
*/}}
{{- define "telos.namespace" -}}
{{- .Values.global.namespace | default "telos" -}}
{{- end -}}

{{/*
Common labels stamped on every object. Keeps `helm ls`/selectors sane and
mirrors Helm's own conventions without dragging in a full library chart.
*/}}
{{- define "telos.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: telos
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/*
Fully-qualified image reference: <registry>/<repository>:<tag>.
Usage: {{ include "telos.image" (dict "root" $ "image" .Values.taskService.image) }}
*/}}
{{- define "telos.image" -}}
{{- $reg := .root.Values.global.imageRegistry | trimSuffix "/" -}}
{{- printf "%s/%s:%s" $reg .image.repository (.image.tag | toString) -}}
{{- end -}}

{{/*
Guard against the Phase 2 placeholder-substitution bug class.
Rejects any value still carrying a literal `${...}` (the un-envsubst'd
placeholder that produced STS ValidationErrors). Empty is allowed — callers
that require a non-empty value use telos.requireArn instead.
Usage: {{ include "telos.assertNoPlaceholder" (dict "val" $v "field" "terraformOutputs.sqsQueueUrl") }}
*/}}
{{- define "telos.assertNoPlaceholder" -}}
{{- $v := .val | toString -}}
{{- if regexMatch "\\$\\{[A-Za-z0-9_]+\\}" $v -}}
{{- fail (printf "TELOS chart: %s is still the literal placeholder %q — populate it from `terraform output` (see values.yaml / README.md). This is the exact envsubst foot-gun documented in plan/phase2.md." .field $v) -}}
{{- end -}}
{{- $v -}}
{{- end -}}
