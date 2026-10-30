# Bloc 3 — Scripts de révision DevOps / MLOps

Chaque script est une fiche commentée découpée en fonctions (une section = une fonction).

```bash
chmod +x *.sh
./05_docker.sh                 # sans argument : liste les fonctions
./05_docker.sh write_compose   # exécute une fonction précise
```

## Correspondance avec le sujet

| Point du sujet | Script |
|---|---|
| 1. Jupyter | `01_jupyter_venv.sh` |
| 2. `export` / `.bashrc` | `02_variables_environnement.sh` |
| 3. Variables d'env dans Python | `02_variables_environnement.sh` |
| 4. Environnements virtuels | `01_jupyter_venv.sh` |
| 5. Requêtes vers une URL (Python & Bash) | `03_requetes_http_curl.sh` |
| 6. `joblib` | `04_joblib.sh` |
| 7. GitLab (repository, `.gitlab-ci.yml`, `gitlab-runner`) | `08_gitlab_ci_runner.sh` |
| 8. Docker (Dockerfile, volumes, compose `depends_on`, DockerHub) | `05_docker.sh` |
| 9. Pytest | `07_pytest.sh` |
| 10. FastAPI + `prometheus-fastapi-instrumentator` | `06_fastapi_pydantic.sh` |
| 11. `pydantic.BaseModel` | `06_fastapi_pydantic.sh` |
| 12. `curl` | `03_requetes_http_curl.sh` |
| 13. Kubernetes (Namespaces, PV, PVC, ConfigMaps, Services, Deployments) | `09_kubernetes.sh` |
| 14. Prometheus (`config/prometheus.yml`, PromQL) | `10_prometheus_promql.sh` |
| 15. Grafana (`datasources/<source>.yml`, dashboard UI) | `11_grafana.sh` |

## Parcours complet (mini-projet TechShop)

Dans un dossier vide, avec le venv activé :

```bash
B=chemin/vers/bloc3
$B/06_fastapi_pydantic.sh install_deps
$B/06_fastapi_pydantic.sh create_app          # app/schemas.py + app/main.py
$B/04_joblib.sh train_and_dump                # train.py + models/model.joblib
$B/07_pytest.sh write_tests && pytest -v      # tests/
$B/10_prometheus_promql.sh write_config       # config/prometheus.yml
$B/11_grafana.sh write_datasource             # grafana/provisioning/datasources/prometheus.yml
$B/05_docker.sh write_dockerfile
$B/05_docker.sh write_compose                 # api + db + prometheus + grafana
docker compose up -d --build
$B/03_requetes_http_curl.sh wait_for_api
$B/03_requetes_http_curl.sh generate_traffic
# → http://localhost:8000/docs | :9090 (Prometheus) | :3000 (Grafana)
$B/11_grafana.sh dashboard_ui_steps           # créer le dashboard à la main
```

`08_gitlab_ci_runner.sh` et `09_kubernetes.sh` sont des copies de `gitlab_linux.sh` et
`kubernetes_dev_setup.sh` (racine du dossier), avec le lanceur de fonctions en plus.
