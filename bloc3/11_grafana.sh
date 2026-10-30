#!/usr/bin/env bash
# =============================================================================
# BLOC 3 — GRAFANA : datasource provisionnée + dashboard depuis l'UI
# =============================================================================
# Sujet : point 15
# Usage : ./11_grafana.sh <fonction>
# =============================================================================

set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_AUTH="${GRAFANA_AUTH:-admin:admin}"      # identifiants par défaut (changés au 1er login)

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 : DATASOURCE — datasources/<source_name>.yml
# ─────────────────────────────────────────────────────────────────────────────
# Grafana lit au démarrage /etc/grafana/provisioning/datasources/*.yml
# → la source de données existe sans clic dans l'UI (reproductible, versionnée).

write_datasource() {
    mkdir -p grafana/provisioning/datasources
    cat > grafana/provisioning/datasources/prometheus.yml <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy                     # c'est le serveur Grafana qui appelle Prometheus
    url: http://prometheus:9090       # nom du service compose (pas localhost !)
    isDefault: true
    editable: true
    jsonData:
      timeInterval: 15s               # = scrape_interval de Prometheus
EOF
}

run_grafana() {
    docker run -d --name grafana -p 3000:3000 \
        -v "$(pwd)/grafana/provisioning/datasources:/etc/grafana/provisioning/datasources:ro" \
        -e GF_SECURITY_ADMIN_PASSWORD=admin \
        grafana/grafana:latest
    # Dans un docker-compose.yml (cf. 05_docker.sh) :
    #   grafana:
    #     image: grafana/grafana:latest
    #     ports: ["3000:3000"]
    #     volumes:
    #       - ./grafana/provisioning/datasources:/etc/grafana/provisioning/datasources:ro
    #     depends_on: [prometheus]
    docker logs grafana 2>&1 | grep -i datasource
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 : VÉRIFIER VIA L'API HTTP
# ─────────────────────────────────────────────────────────────────────────────

check_api() {
    curl -s "${GRAFANA_URL}/api/health"
    curl -s -u "${GRAFANA_AUTH}" "${GRAFANA_URL}/api/datasources" | python3 -m json.tool
    curl -s -u "${GRAFANA_AUTH}" "${GRAFANA_URL}/api/search?type=dash-db" | python3 -m json.tool
    # Exporter un dashboard en JSON (récupérer l'uid via /api/search)
    # curl -s -u "${GRAFANA_AUTH}" "${GRAFANA_URL}/api/dashboards/uid/<UID>" > dashboard.json
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 : CRÉER UN DASHBOARD DEPUIS L'UI (pas à pas)
# ─────────────────────────────────────────────────────────────────────────────

dashboard_ui_steps() {
    cat <<'EOF'
1. Ouvrir http://localhost:3000 → login admin / admin (changer le mot de passe)
2. Connections > Data sources : "Prometheus" doit déjà être là (provisioning)
   → bouton "Save & test" : "Successfully queried the Prometheus API"
3. Dashboards > New > New dashboard > Add visualization
4. Choisir la datasource Prometheus
5. Onglet Query : passer en mode "Code" et coller une requête PromQL
6. À droite : type de visualisation, Title, Unit (Standard options), Thresholds
7. "Apply" (ou Back to dashboard), puis icône disquette "Save dashboard" → nom : TechShop API
8. En haut à droite : plage de temps (Last 15 minutes) + refresh auto (5s)

Panels conseillés (générer du trafic avant : 03_requetes_http_curl.sh generate_traffic)
┌──────────────────────┬─────────────┬───────────────────────────────────────────────────────────────┐
│ Panel                │ Visu        │ PromQL                                                        │
├──────────────────────┼─────────────┼───────────────────────────────────────────────────────────────┤
│ API UP               │ Stat        │ up{job="techshop-api"}                                        │
│ Requêtes/s par route │ Time series │ sum by (handler) (rate(http_requests_total[1m]))              │
│ Taux d'erreur 5xx %  │ Gauge       │ 100*sum(rate(http_requests_total{status=~"5.."}[5m]))         │
│                      │             │   /sum(rate(http_requests_total[5m]))                         │
│ Latence p95 (s)      │ Time series │ histogram_quantile(0.95, sum by (le)                          │
│                      │             │   (rate(http_request_duration_seconds_bucket[5m])))           │
│ Prédictions churn    │ Bar chart   │ sum by (churn) (increase(techshop_predictions_total[1h]))     │
│ Mémoire (Mo)         │ Stat        │ process_resident_memory_bytes/1024/1024                       │
└──────────────────────┴─────────────┴───────────────────────────────────────────────────────────────┘

Astuces :
- Legend : {{handler}} pour afficher le label dans la légende
- Variables de dashboard : Settings > Variables > Query : label_values(http_requests_total, handler)
  puis utiliser {handler="$handler"} dans les requêtes
- Partager / sauvegarder : Share > Export > JSON (à versionner dans Git)
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# Lancement : ./11_grafana.sh <fonction>
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ $# -eq 0 ]]; then
        echo "Usage : $0 <fonction>"; declare -F | awk '{print "  - " $3}'
    else
        "$@"
    fi
fi
