#!/usr/bin/env bash
# =============================================================================
# BLOC 3 — PROMETHEUS : config/prometheus.yml + PromQL
# =============================================================================
# Sujet : point 14 (instrumentator → voir 06_fastapi_pydantic.sh)
# Usage : ./10_prometheus_promql.sh <fonction>
# =============================================================================

set -euo pipefail

PROM_URL="${PROM_URL:-http://localhost:9090}"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 : FONCTIONNEMENT
# ─────────────────────────────────────────────────────────────────────────────
# Prometheus fonctionne en PULL : toutes les scrape_interval, il appelle
# GET http://<cible>/metrics et stocke les séries temporelles.
# Types de métriques :
#   Counter   : ne fait que monter (requêtes, erreurs)      → toujours rate()
#   Gauge     : monte et descend (mémoire, file d'attente)
#   Histogram : buckets _bucket / _sum / _count (latences)  → histogram_quantile()
#   Summary   : quantiles calculés côté client

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 : config/prometheus.yml
# ─────────────────────────────────────────────────────────────────────────────

write_config() {
    mkdir -p config
    cat > config/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s        # fréquence de scraping
  evaluation_interval: 15s    # fréquence d'évaluation des règles

scrape_configs:
  - job_name: 'prometheus'    # Prometheus se surveille lui-même
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'techshop-api'
    metrics_path: /metrics     # (défaut)
    scrape_interval: 5s
    static_configs:
      - targets: ['api:8000']  # nom du SERVICE docker compose (pas localhost !)
        labels:
          env: 'dev'

# rule_files:
#   - 'alert_rules.yml'
EOF
}

run_prometheus() {
    # Seul (hors compose) — si l'API tourne sur l'hôte, cibler host.docker.internal:8000
    docker run -d --name prometheus -p 9090:9090 \
        -v "$(pwd)/config/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
        prom/prometheus:latest
    # Vérifier la config sans démarrer
    docker run --rm -v "$(pwd)/config:/cfg" --entrypoint promtool prom/prometheus:latest \
        check config /cfg/prometheus.yml
    # UI : http://localhost:9090  → Status > Targets (doit être UP)
    # Recharger la config : docker restart prometheus
    #   (ou curl -X POST ${PROM_URL}/-/reload si --web.enable-lifecycle)
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 : PromQL — REQUÊTES À CONNAÎTRE
# ─────────────────────────────────────────────────────────────────────────────

promql_cheatsheet() {
    cat <<'EOF'
# ── Sélection ─────────────────────────────────────────────
up                                                   # 1 = cible joignable, 0 = down
http_requests_total                                  # instant vector
http_requests_total{handler="/predict", method="POST"}
http_requests_total{status=~"5.."}                   # regex (=~) ; != et !~ aussi
http_requests_total[5m]                              # range vector (5 dernières min)

# ── Taux (counters) ───────────────────────────────────────
rate(http_requests_total[1m])                        # req/s moyenne sur 1 min
irate(http_requests_total[1m])                       # req/s instantané (2 derniers points)
increase(http_requests_total[1h])                    # nb de requêtes sur 1 h

# ── Agrégation ────────────────────────────────────────────
sum(rate(http_requests_total[1m]))                   # débit total
sum by (handler) (rate(http_requests_total[1m]))     # par endpoint
sum without (instance) (rate(http_requests_total[1m]))
topk(3, sum by (handler) (rate(http_requests_total[5m])))
count(up == 1)                                       # nb de cibles UP

# ── Taux d'erreur (%) ─────────────────────────────────────
100 * sum(rate(http_requests_total{status=~"5.."}[5m]))
    / sum(rate(http_requests_total[5m]))

# ── Latence (histogram) ───────────────────────────────────
histogram_quantile(0.95,
  sum by (le) (rate(http_request_duration_seconds_bucket[5m])))     # p95
rate(http_request_duration_seconds_sum[5m])
  / rate(http_request_duration_seconds_count[5m])                   # latence moyenne

# ── Métrique métier ───────────────────────────────────────
sum by (churn) (increase(techshop_predictions_total[1h]))

# ── Ressources du process ─────────────────────────────────
process_resident_memory_bytes / 1024 / 1024          # Mo
rate(process_cpu_seconds_total[1m])
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 : INTERROGER PROMETHEUS PAR SON API HTTP (curl)
# ─────────────────────────────────────────────────────────────────────────────

query_api() {
    curl -s "${PROM_URL}/-/healthy"
    curl -s "${PROM_URL}/api/v1/targets" | python3 -m json.tool | grep -E '"(job|health)"'

    # Requête instantanée (--data-urlencode gère les { } " de PromQL)
    curl -s -G "${PROM_URL}/api/v1/query" \
         --data-urlencode 'query=sum by (handler) (rate(http_requests_total[1m]))' \
         | python3 -m json.tool

    # Requête sur une plage (graphe)
    curl -s -G "${PROM_URL}/api/v1/query_range" \
         --data-urlencode 'query=rate(http_requests_total[1m])' \
         --data-urlencode "start=$(date -d '-10 min' +%s)" \
         --data-urlencode "end=$(date +%s)" \
         --data-urlencode 'step=15s' | head -c 500; echo

    curl -s "${PROM_URL}/api/v1/label/__name__/values" | python3 -m json.tool | grep http_
}

# ─────────────────────────────────────────────────────────────────────────────
# Lancement : ./10_prometheus_promql.sh <fonction>
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ $# -eq 0 ]]; then
        echo "Usage : $0 <fonction>"; declare -F | awk '{print "  - " $3}'
    else
        "$@"
    fi
fi
