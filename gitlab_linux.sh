#!/usr/bin/env bash
# =============================================================================
# GUIDE D'INSTALLATION ET D'UTILISATION DE GITLAB CE SUR LINUX
# =============================================================================
# Distribution cible : Ubuntu 22.04 LTS / Debian 12
# Ce script est documenté pour servir de fiche de révision.
# Lire les sections, exécuter les blocs commentés selon vos besoins.
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 : INSTALLATION DE GITLAB CE
# ─────────────────────────────────────────────────────────────────────────────

install_gitlab() {
    echo "=== Installation de GitLab CE ==="

    # 1. Dépendances système
    sudo apt-get update -y
    sudo apt-get install -y curl ca-certificates tzdata perl

    # 2. Ajout du dépôt officiel GitLab
    curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh \
        | sudo bash

    # 3. Installation (remplacer l'URL par votre domaine ou IP)
    GITLAB_URL="http://gitlab.example.com"
    sudo EXTERNAL_URL="${GITLAB_URL}" apt-get install -y gitlab-ce

    # 4. Démarrage et initialisation (peut prendre 2-5 minutes)
    sudo gitlab-ctl reconfigure

    echo "GitLab accessible sur : ${GITLAB_URL}"
    echo "Mot de passe root initial :"
    sudo cat /etc/gitlab/initial_root_password
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 : COMMANDES GITLAB-CTL (administration)
# ─────────────────────────────────────────────────────────────────────────────
# Ces commandes gèrent le cycle de vie de l'instance GitLab.

gitlab_ctl_examples() {
    sudo gitlab-ctl status          # état de tous les services
    sudo gitlab-ctl start           # démarrer tous les services
    sudo gitlab-ctl stop            # arrêter
    sudo gitlab-ctl restart         # redémarrer
    sudo gitlab-ctl reconfigure     # appliquer les changements de /etc/gitlab/gitlab.rb
    sudo gitlab-ctl tail            # suivre tous les logs en temps réel
    sudo gitlab-ctl tail nginx      # logs d'un service spécifique
    sudo gitlab-ctl backup-etc      # sauvegarder la configuration
    sudo gitlab-backup create       # sauvegarder les données (repos, BDD, uploads)
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 : CONFIGURATION (/etc/gitlab/gitlab.rb)
# ─────────────────────────────────────────────────────────────────────────────
# Après chaque modification : sudo gitlab-ctl reconfigure

configure_gitlab() {
    # Exemple de modifications courantes dans /etc/gitlab/gitlab.rb :
    cat <<'EOF'
## /etc/gitlab/gitlab.rb — extraits importants

external_url 'http://gitlab.mondomaine.fr'   # URL publique

# SMTP (notifications email)
gitlab_rails['smtp_enable']     = true
gitlab_rails['smtp_address']    = "smtp.gmail.com"
gitlab_rails['smtp_port']       = 587
gitlab_rails['smtp_user_name']  = "mon@gmail.com"
gitlab_rails['smtp_password']   = "app_password"
gitlab_rails['smtp_tls']        = false
gitlab_rails['smtp_starttls_auto'] = true

# Réduction de la consommation RAM (utile en dev sur petit serveur)
puma['worker_processes'] = 2
sidekiq['max_concurrency'] = 10
postgresql['shared_buffers'] = "256MB"
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 : GIT — UTILISATION D'UN REPOSITORY GITLAB
# ─────────────────────────────────────────────────────────────────────────────

git_basics() {
    # Configurer l'identité (une seule fois sur la machine)
    git config --global user.name  "Prénom Nom"
    git config --global user.email "email@example.com"

    # Cloner un dépôt GitLab
    git clone http://gitlab.example.com/groupe/projet.git
    cd projet

    # Cycle de travail quotidien
    git status                          # voir les modifications
    git add fichier.py                  # ajouter au staging
    git add .                           # ajouter tout
    git commit -m "feat: ajouter API"   # créer un commit
    git push origin main                # pousser vers GitLab

    # Branches
    git checkout -b feature/ma-feature  # créer et basculer sur une branche
    git push -u origin feature/ma-feature
    git checkout main                   # revenir sur main
    git merge feature/ma-feature        # fusionner
    git branch -d feature/ma-feature    # supprimer la branche locale

    # Tags
    git tag -a v1.0.0 -m "Version 1.0.0"
    git push origin v1.0.0

    # Voir l'historique
    git log --oneline --graph --all
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 : CLÉS SSH POUR GITLAB
# ─────────────────────────────────────────────────────────────────────────────

setup_ssh_key() {
    # Générer une clé SSH Ed25519 (recommandée)
    ssh-keygen -t ed25519 -C "email@example.com" -f ~/.ssh/id_ed25519_gitlab

    # Afficher la clé publique à coller dans GitLab (Settings > SSH Keys)
    cat ~/.ssh/id_ed25519_gitlab.pub

    # Ajouter au ssh-agent
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_ed25519_gitlab

    # Configurer ~/.ssh/config pour GitLab
    cat >>~/.ssh/config <<'EOF'
Host gitlab.example.com
    HostName gitlab.example.com
    User git
    IdentityFile ~/.ssh/id_ed25519_gitlab
EOF

    # Tester la connexion
    ssh -T git@gitlab.example.com
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6 : PIPELINE CI/CD — .gitlab-ci.yml
# ─────────────────────────────────────────────────────────────────────────────
# Le fichier .gitlab-ci.yml doit être à la RACINE du dépôt.
# Chaque push déclenche automatiquement le pipeline.

show_gitlab_ci_examples() {
    cat <<'EOF'
# ════════════════════════════════════════════════════════════════
# .gitlab-ci.yml — Pipeline CI/CD complet
# ════════════════════════════════════════════════════════════════

# Image Docker utilisée par défaut pour tous les jobs
image: python:3.11-slim

# Variables d'environnement disponibles dans tous les jobs
variables:
  PIP_CACHE_DIR: "$CI_PROJECT_DIR/.cache/pip"
  APP_ENV: "ci"
  MODEL_PATH: "./models/churn.joblib"

# Cache pip entre les pipelines (accélère les builds)
cache:
  paths:
    - .cache/pip
    - venv/

# ── Étapes du pipeline (ordre d'exécution) ──────────────────────
stages:
  - install
  - test
  - build
  - deploy

# ── Job 1 : installation des dépendances ────────────────────────
install_deps:
  stage: install
  script:
    - python -m venv venv
    - source venv/bin/activate
    - pip install --upgrade pip
    - pip install -r requirements.txt
  artifacts:
    paths:
      - venv/
    expire_in: 1 hour

# ── Job 2 : tests unitaires avec pytest ─────────────────────────
unit_tests:
  stage: test
  needs: [install_deps]
  script:
    - source venv/bin/activate
    - pytest tests/ -v --tb=short --junitxml=report.xml
  artifacts:
    reports:
      junit: report.xml   # GitLab affiche les résultats dans l'UI
    when: always

# ── Job 3 : linting ─────────────────────────────────────────────
lint:
  stage: test
  needs: [install_deps]
  script:
    - source venv/bin/activate
    - pip install flake8
    - flake8 src/ --max-line-length=100 --exclude=venv/

# ── Job 4 : build de l'image Docker (Docker-in-Docker + TLS) ────
# PRÉREQUIS CÔTÉ RUNNER (sinon le job échoue) — voir show_runner_config :
#   - executor = "docker"
#   - privileged = true            → dind a besoin des droits noyau complets
#   - volumes contient "/certs/client" → partage des certs client job ↔ dind
build_image:
  stage: build
  image: docker:24               # container du job : CLIENT docker uniquement
  services:
    - name: docker:24-dind       # container annexe : DÉMON docker
      alias: docker              # nom d'hôte du démon vu depuis le job
  variables:
    # Le démon dind génère CA + certs serveur/client dans ce dossier au démarrage
    # et écoute en TLS sur le port 2376 (au lieu de 2375 en clair).
    DOCKER_TLS_CERTDIR: "/certs"
    # Côté client, l'image docker:24 déduit ces 3 valeurs toute seule ;
    # on les écrit explicitement pour que ce soit lisible / débogable :
    DOCKER_HOST: "tcp://docker:2376"      # où joindre le démon (alias ci-dessus)
    DOCKER_TLS_VERIFY: "1"                # exiger TLS + vérifier le cert serveur
    DOCKER_CERT_PATH: "/certs/client"     # cert client à présenter au démon
    DOCKER_DRIVER: overlay2               # driver de stockage performant
  before_script:
    # Le démon dind peut mettre quelques secondes à démarrer : on attend
    # qu'il réponde avant d'aller plus loin (évite "Cannot connect to the Docker daemon").
    - until docker info >/dev/null 2>&1; do echo "Attente du démon dind..."; sleep 1; done
    # Login via stdin : le mot de passe n'apparaît ni dans `ps` ni dans les logs.
    # CI_REGISTRY_USER / CI_REGISTRY_PASSWORD : identifiants temporaires fournis par GitLab
    - echo "$CI_REGISTRY_PASSWORD" | docker login -u "$CI_REGISTRY_USER" --password-stdin "$CI_REGISTRY"
  script:
    # UN SEUL build, deux tags sur la même image (même ID, aucun travail en double) :
    #   - $CI_COMMIT_SHA : version immuable et traçable (rollback possible)
    #   - latest         : pointe toujours sur la dernière version de main
    - docker build -t "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA" -t "$CI_REGISTRY_IMAGE:latest" .
    # Le push du 2e tag est quasi instantané : les couches sont déjà dans le registry
    - docker push "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA"
    - docker push "$CI_REGISTRY_IMAGE:latest"
  only:
    - main                       # on ne publie d'image que depuis main

# ── Job 5 : déploiement (manuel) ────────────────────────────────
deploy_prod:
  stage: deploy
  script:
    - echo "Déploiement sur le serveur de production..."
    - ssh deploy@prod.server.fr "docker pull $CI_REGISTRY_IMAGE:latest && docker-compose up -d"
  environment:
    name: production
    url: https://app.mondomaine.fr
  when: manual    # déclenché manuellement depuis l'UI GitLab
  only:
    - main

# ── Job conditionnel (uniquement sur MR) ────────────────────────
review_app:
  stage: deploy
  script:
    - echo "Déploiement de l'environnement de review..."
  environment:
    name: review/$CI_COMMIT_REF_NAME
    on_stop: stop_review
  only:
    - merge_requests

stop_review:
  stage: deploy
  script:
    - echo "Suppression de l'environnement de review..."
  environment:
    name: review/$CI_COMMIT_REF_NAME
    action: stop
  when: manual
  only:
    - merge_requests
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6 bis : RULES — CONTRÔLER QUAND UN JOB S'EXÉCUTE
# ─────────────────────────────────────────────────────────────────────────────
# `rules` remplace `only` / `except` (déconseillés, ne pas mélanger dans un job).
#
# Fonctionnement :
#   - les règles sont évaluées DANS L'ORDRE, la 1re qui matche gagne
#   - si AUCUNE règle ne matche → le job n'est PAS ajouté au pipeline
#   - une règle peut combiner : if / changes / exists (ET logique entre eux)
#   - et définir : when / allow_failure / variables / start_in / needs
#
# Valeurs de `when` :
#   on_success (défaut) : si les jobs des stages précédents ont réussi
#   on_failure          : seulement si un job précédent a échoué
#   always              : quoi qu'il arrive
#   manual              : bouton ▶ dans l'UI
#   delayed             : lancé après `start_in` (ex: "30 minutes")
#   never               : ne jamais lancer
#
# Valeurs utiles de $CI_PIPELINE_SOURCE :
#   push | merge_request_event | schedule | web (bouton "Run pipeline")
#   | api | trigger | pipeline (multi-projet) | parent_pipeline (enfant)
#
# Opérateurs dans `if` : == != =~ (regex) !~ && || et parenthèses
#   Variable non définie → vaut null ; tester l'existence : if: $MA_VAR

show_gitlab_ci_rules() {
    cat <<'EOF'
# ════════════════════════════════════════════════════════════════
# .gitlab-ci.yml — Exemples de rules
# ════════════════════════════════════════════════════════════════

# ── workflow:rules — décide si le PIPELINE ENTIER est créé ──────
# Évite les pipelines en double (un pour le push + un pour la MR)
workflow:
  rules:
    - if: $CI_COMMIT_MESSAGE =~ /\[skip ci\]/      # commit "[skip ci]" → pas de pipeline
      when: never
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"   # pipelines de MR
    - if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS   # push sur une branche qui
      when: never                                        # a déjà une MR → doublon évité
    - if: $CI_COMMIT_BRANCH                        # push sur une branche
    - if: $CI_COMMIT_TAG                           # création d'un tag
    - if: $CI_PIPELINE_SOURCE == "schedule"        # pipeline planifié
    - if: $CI_PIPELINE_SOURCE == "web"             # lancé depuis l'UI

# ── Règles réutilisables (ancres YAML) ──────────────────────────
.rules_mr_ou_main: &rules_mr_ou_main
  - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

stages:
  - test
  - build
  - deploy
  - notify

# ── 1. Tests : sur MR et sur main, avec l'ancre ─────────────────
unit_tests:
  stage: test
  script:
    - pytest tests/ -v
  rules: *rules_mr_ou_main

# ── 2. Job "tout-terrain" : exemple qui couvre tous les cas ─────
build_image:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
  script:
    - docker build -t "$CI_REGISTRY_IMAGE:$IMAGE_TAG" .
    - docker push "$CI_REGISTRY_IMAGE:$IMAGE_TAG"
  rules:
    # a) Jamais sur un pipeline planifié (nightly = tests uniquement)
    - if: $CI_PIPELINE_SOURCE == "schedule"
      when: never

    # b) Interrupteur d'urgence : variable SKIP_BUILD="true" → on saute
    - if: $SKIP_BUILD == "true"
      when: never

    # c) Tag de version sémantique (v1.2.3) → image taguée avec la version
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
      variables:
        IMAGE_TAG: $CI_COMMIT_TAG

    # d) Branche main → image "latest", seulement si le code a changé
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      changes:
        - src/**/*
        - Dockerfile
        - requirements.txt
      variables:
        IMAGE_TAG: latest

    # e) MR qui touche au Dockerfile → build de vérif, échec toléré
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes:
        paths:
          - Dockerfile
        compare_to: refs/heads/main   # comparer à main (pas au commit précédent)
      variables:
        IMAGE_TAG: mr-$CI_MERGE_REQUEST_IID
      allow_failure: true

    # f) Branches feature/* → manuel (bouton ▶), ne bloque pas le pipeline
    - if: $CI_COMMIT_BRANCH =~ /^feature\//
      when: manual
      allow_failure: true
      variables:
        IMAGE_TAG: $CI_COMMIT_SHORT_SHA

    # g) Filet de sécurité : tout le reste → pas de job
    - when: never

# ── 3. Job conditionné à l'existence d'un fichier ───────────────
docs:
  stage: build
  script:
    - mkdocs build
  rules:
    - exists:
        - mkdocs.yml          # job créé seulement si le fichier est dans le dépôt

# ── 4. Déploiement prod : manuel sur tag, bloquant ──────────────
deploy_prod:
  stage: deploy
  script:
    - ./deploy.sh production
  environment:
    name: production
  rules:
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
      when: manual
      allow_failure: false    # le pipeline reste "bloqué" tant qu'on ne valide pas

# ── 5. Déploiement staging différé (laisse le temps d'annuler) ──
deploy_staging:
  stage: deploy
  script:
    - ./deploy.sh staging
  environment:
    name: staging
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      when: delayed
      start_in: 10 minutes

# ── 6. Notification en cas d'échec uniquement ───────────────────
notify_failure:
  stage: notify
  script:
    - 'curl -X POST -H "Content-Type: application/json" -d "{\"text\":\"Pipeline $CI_PIPELINE_ID KO sur $CI_COMMIT_REF_NAME\"}" "$WEBHOOK_URL"'
  rules:
    - if: $WEBHOOK_URL          # seulement si la variable est définie
      when: on_failure

# ── 7. Nettoyage systématique ───────────────────────────────────
cleanup:
  stage: notify
  script:
    - echo "Nettoyage des ressources temporaires..."
  rules:
    - when: always

# ── Équivalences only/except → rules ────────────────────────────
#   only: [main]              →  rules: - if: $CI_COMMIT_BRANCH == "main"
#   only: [tags]              →  rules: - if: $CI_COMMIT_TAG
#   only: [merge_requests]    →  rules: - if: $CI_PIPELINE_SOURCE == "merge_request_event"
#   except: [schedules]       →  rules: - if: $CI_PIPELINE_SOURCE == "schedule"
#                                           when: never
#                                         - when: on_success
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7 : GITLAB RUNNER — INSTALLATION ET ENREGISTREMENT
# ─────────────────────────────────────────────────────────────────────────────
# Le Runner est l'agent qui exécute les jobs CI/CD.
# Il peut tourner sur n'importe quelle machine (serveur, VM, laptop).

install_gitlab_runner() {
    echo "=== Installation de gitlab-runner ==="

    # Ubuntu/Debian
    curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" \
        | sudo bash
    sudo apt-get install -y gitlab-runner

    # Vérification
    gitlab-runner --version
    sudo gitlab-runner status
}

register_runner() {
    echo "=== Enregistrement du Runner ==="
    # Récupérer le token dans GitLab : Settings > CI/CD > Runners > Registration token

    sudo gitlab-runner register \
        --url "http://gitlab.example.com" \
        --registration-token "VOTRE_TOKEN_ICI" \
        --description "Mon Runner Linux" \
        --executor "docker" \
        --docker-image "python:3.11-slim" \
        --docker-privileged \
        --docker-volumes "/certs/client" \
        --docker-volumes "/cache" \
        --tag-list "linux,docker,python"
    # --docker-privileged             : requis pour Docker-in-Docker (job build_image)
    # --docker-volumes "/certs/client": partage les certs TLS entre le job et le service dind
    # --docker-volumes "/cache"       : dossier de cache persistant entre les jobs

    # Ou en mode interactif (recommandé pour découvrir les options) :
    # sudo gitlab-runner register
}

gitlab_runner_commands() {
    # Gestion du service
    sudo gitlab-runner start            # démarrer
    sudo gitlab-runner stop             # arrêter
    sudo gitlab-runner restart          # redémarrer
    sudo gitlab-runner status           # état

    # Runners enregistrés
    sudo gitlab-runner list             # lister les runners
    sudo gitlab-runner verify           # vérifier la connexion GitLab
    sudo gitlab-runner unregister --name "Mon Runner Linux"  # désinscrire

    # Débogage : lancer un job manuellement
    sudo gitlab-runner exec docker unit_tests   # exécute le job 'unit_tests' localement
}

# ── Configuration du Runner (/etc/gitlab-runner/config.toml) ────
show_runner_config() {
    cat <<'EOF'
# /etc/gitlab-runner/config.toml
concurrent = 4     # nb de jobs exécutés en parallèle

[[runners]]
  name = "Mon Runner"
  url = "http://gitlab.example.com"
  token = "TOKEN"
  executor = "docker"

  [runners.docker]
    image = "python:3.11-slim"         # image par défaut si le job n'en précise pas
    tls_verify = false                 # TLS entre runner et démon de l'HÔTE (local, inutile)

    # Docker-in-Docker : le démon dind doit manipuler cgroups, montages, réseau…
    # → impossible sans mode privilégié. Sans ça : "dockerd: permission denied".
    privileged = true

    # "/cache"        : cache persistant entre jobs
    # "/certs/client" : volume partagé entre le container du job et le service
    #                   dind → le client récupère le cert généré par le démon.
    #                   Sans ça : erreur TLS "certificate signed by unknown authority"
    #                   ou "open /certs/client/ca.pem: no such file".
    volumes = ["/cache", "/certs/client"]

    pull_policy = "if-not-present"     # évite de re-pull les images à chaque job

# ── Alternative : montage du socket (pas de dind, pas de certs) ──
# volumes = ["/cache", "/var/run/docker.sock:/var/run/docker.sock"]
# privileged = false
# → le job pilote directement le Docker de l'HÔTE : plus rapide (cache des
#   couches conservé) mais AUCUNE isolation (un job peut voir/tuer tous les
#   containers de la machine). Dans ce cas, retirer du job le `services:`
#   et les variables DOCKER_TLS_CERTDIR / DOCKER_HOST / DOCKER_TLS_VERIFY.
#   Ne pas combiner les deux approches.
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8 : VARIABLES CI/CD PRÉDÉFINIES UTILES
# ─────────────────────────────────────────────────────────────────────────────

show_predefined_vars() {
    cat <<'EOF'
# Variables automatiquement disponibles dans les jobs CI/CD :

CI_COMMIT_SHA          # hash complet du commit (ex: a1b2c3d...)
CI_COMMIT_SHORT_SHA    # 8 premiers caractères
CI_COMMIT_BRANCH       # nom de la branche
CI_COMMIT_REF_NAME     # branche ou tag
CI_COMMIT_MESSAGE      # message du commit
CI_PROJECT_NAME        # nom du projet
CI_PROJECT_DIR         # répertoire de travail (/builds/groupe/projet)
CI_REGISTRY            # URL du registry Docker GitLab
CI_REGISTRY_IMAGE      # image complète (registry/groupe/projet)
CI_REGISTRY_USER       # utilisateur registry
CI_REGISTRY_PASSWORD   # mot de passe registry
CI_PIPELINE_ID         # ID du pipeline
CI_JOB_NAME            # nom du job actuel
CI_ENVIRONMENT_NAME    # nom de l'environnement (si défini)

# Variables personnalisées : Settings > CI/CD > Variables
# (masquées, non affichées dans les logs)
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 9 : API GITLAB (interaction via curl)
# ─────────────────────────────────────────────────────────────────────────────

gitlab_api_examples() {
    GITLAB_URL="http://gitlab.example.com"
    TOKEN="votre_personal_access_token"

    # Lister ses projets
    curl -s -H "PRIVATE-TOKEN: ${TOKEN}" \
        "${GITLAB_URL}/api/v4/projects?owned=true" | python3 -m json.tool

    # Créer un projet
    curl -s -X POST \
        -H "PRIVATE-TOKEN: ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"name":"mon-projet","visibility":"private"}' \
        "${GITLAB_URL}/api/v4/projects"

    # Lister les pipelines d'un projet (ID=42)
    curl -s -H "PRIVATE-TOKEN: ${TOKEN}" \
        "${GITLAB_URL}/api/v4/projects/42/pipelines"

    # Déclencher un pipeline manuellement
    curl -s -X POST \
        -H "PRIVATE-TOKEN: ${TOKEN}" \
        -F "ref=main" \
        "${GITLAB_URL}/api/v4/projects/42/pipeline"
}

# ─────────────────────────────────────────────────────────────────────────────
# POINT D'ENTRÉE
# ─────────────────────────────────────────────────────────────────────────────

echo "=============================================="
echo " Fiche GitLab CE — Linux"
echo " Fonctions disponibles :"
echo "   install_gitlab          → installer GitLab CE"
echo "   install_gitlab_runner   → installer le runner"
echo "   register_runner         → enregistrer le runner"
echo "   gitlab_runner_commands  → commandes runner"
echo "   show_gitlab_ci_examples → afficher .gitlab-ci.yml"
echo "   show_gitlab_ci_rules    → exemples de rules (quand lancer un job)"
echo "   git_basics              → commandes git"
echo "   setup_ssh_key           → configurer SSH"
echo "   gitlab_api_examples     → exemples API REST"
echo "=============================================="
