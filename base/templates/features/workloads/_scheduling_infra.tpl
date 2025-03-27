{{- define "base.workloads.scheduling" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}


{{- if include "base.lib.utils.isEnabled" (dig "scheduling" dict $workload ) -}}
{{- $nodepools := (list "common" "bursty" "volatile") }}
{{- if not (has $workload.scheduling.nodepool $nodepools) }}
  {{- fail (printf "workload scheduling must be one of %v(workload: %s)" $nodepools $workloadId) }}
{{- end }}
resources:
  controllers:
    {{$workloadId}}:
      pod:
      {{- if or (eq $workload.scheduling.nodepool "volatile") (eq $workload.scheduling.nodepool "bursty") (include "base.lib.utils.isEnabled" $workload.scheduling.podSpreadingForHA) }}
        affinity:
          {{- if or (eq $workload.scheduling.nodepool "volatile") (eq $workload.scheduling.nodepool "bursty") }}
          nodeAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
              nodeSelectorTerms:
              - matchExpressions:
                {{- if eq $workload.scheduling.nodepool "volatile" }}
                - key: cloud.blabla.io/k8s-volatile
                  operator: Exists
                 {{- else if eq $workload.scheduling.nodepool "bursty" }}
                - key: dedicated
                  operator: In
                  values:
                  - bursty
                 {{- end }}
          {{- end }}

          {{- if include "base.lib.utils.isEnabled" $workload.scheduling.podSpreadingForHA }}
          podAntiAffinity:
            preferredDuringSchedulingIgnoredDuringExecution:
              - podAffinityTerm:
                  labelSelector:
                    matchExpressions:
                      - key: app
                        operator: In
                        values:
                        - {{ $rootContext.Release.Name }}
                      - key: app.kubernetes.io/component
                        operator: In
                        values:
                        - {{ $workloadId }}
                  topologyKey: kubernetes.io/hostname
                weight: 50
          {{- end }}
      {{- end }}

      {{- if include "base.lib.utils.isEnabled" $workload.scheduling.podSpreadingForHA }}
        topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: "topology.kubernetes.io/zone"
          whenUnsatisfiable: ScheduleAnyway     # toleration zone issue
          labelSelector:
            matchLabels:
              app.kubernetes.io/component: {{ $workloadId }}
              {{- include "base.lib.metadata.selectorLabels" $rootContext | nindent 14 }}
        - maxSkew: {{ $workload.scheduling.podSpreadingForHA.hostnameMaxSkew }}
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule      # clusterAutoscaler will start a new node if needed
          labelSelector:
            matchLabels:
              app.kubernetes.io/component: {{ $workloadId }}
              {{- include "base.lib.metadata.selectorLabels" $rootContext | nindent 14 }}
      {{- end }}

      {{- if or (eq $workload.scheduling.nodepool "volatile") (eq $workload.scheduling.nodepool "bursty") }}
        tolerations:
        - effect: NoSchedule
          operator: Equal
          {{- if eq $workload.scheduling.nodepool "volatile" }}
          key: cloud.blabla.io/k8s-volatile
          value: "true"
          {{- else if eq $workload.scheduling.nodepool "bursty" }}
          key: dedicated
          value: "bursty"
          {{- end }}
      {{- end }}


{{- end -}}
{{- end }}
