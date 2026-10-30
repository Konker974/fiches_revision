#!/usr/bin/env bash
# =============================================================================
# KUBERNETES EN MODE DEV — NŒUD UNIQUE (minikube + kubectl)
# =============================================================================
# Ce script couvre l'installation et l'utilisation de Kubernetes en local
# via minikube (le standard pour le dev sur machine unique).
#
# Prérequis : Docker installé, 2 CPU min, 2 Go RAM libres
# OS cible   : Ubuntu 22.04 / Debian 12
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 : INSTALLATION DE KUBECTL
# ─────────────────────────────────────────────────────────────────────────────

install_kubectl() {
    echo "=== Installation de kubectl ==="

    # Télécharger la dernière version stable
    curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

    # Vérifier l'intégrité
    curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check

    # Installer
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl kubectl.sha256

    kubectl version --client
    echo "kubectl installé !"

    # Autocomplétion bash (ajouter dans ~/.bashrc)
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl'                   >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 : INSTALLATION DE MINIKUBE
# ─────────────────────────────────────────────────────────────────────────────

install_minikube() {
    echo "=== Installation de minikube ==="

    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm minikube-linux-amd64

    minikube version
    echo "minikube installé !"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 : DÉMARRAGE DU CLUSTER MINIKUBE
# ─────────────────────────────────────────────────────────────────────────────

start_minikube() {
    echo "=== Démarrage du cluster minikube ==="

    # Driver recommandé : docker (pas besoin de VirtualBox)
    minikube start \
        --driver=docker \
        --cpus=2 \
        --memory=4096 \
        --disk-size=20g \
        --kubernetes-version=v1.29.0

    # Vérifier que le cluster est prêt
    minikube status
    kubectl cluster-info
    kubectl get nodes
}

minikube_commands() {
    minikube start               # démarrer
    minikube stop                # arrêter (préserve l'état)
    minikube delete              # supprimer le cluster
    minikube pause               # mettre en pause (libère CPU)
    minikube unpause             # reprendre
    minikube status              # état du cluster
    minikube dashboard           # ouvrir le dashboard Kubernetes dans le navigateur
    minikube ip                  # IP du nœud minikube
    minikube logs                # logs minikube
    minikube addons list         # extensions disponibles
    minikube addons enable metrics-server   # activer les métriques
    minikube addons enable ingress          # activer l'ingress controller

    # Accéder à un service exposé
    minikube service mon-service --url
    minikube tunnel              # expose les LoadBalancers sur localhost

    # Utiliser le registry Docker interne
    eval $(minikube docker-env)  # pointer vers le Docker de minikube
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 : NAMESPACES
# ─────────────────────────────────────────────────────────────────────────────
# Les namespaces isolent les ressources (équipes, environnements, projets).
# Namespaces par défaut : default, kube-system, kube-public

kubectl_namespaces() {
    # Lister
    kubectl get namespaces

    # Créer via commande
    kubectl create namespace techshop-dev
    kubectl create namespace techshop-prod

    # Créer via YAML (recommandé)
    cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: techshop-dev
  labels:
    env: development
    team: backend
EOF

    # Travailler dans un namespace
    kubectl get pods -n techshop-dev
    kubectl get all -n techshop-dev

    # Changer le namespace par défaut du contexte
    kubectl config set-context --current --namespace=techshop-dev

    # Supprimer un namespace (supprime TOUTES les ressources dedans !)
    kubectl delete namespace techshop-dev
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 : PERSISTENTVOLUME (PV) & PERSISTENTVOLUMECLAIM (PVC)
# ─────────────────────────────────────────────────────────────────────────────
# PV  : ressource de stockage (provisionnée par l'admin)
# PVC : demande de stockage (faite par le développeur)
# StorageClass : provisionnement automatique (minikube a 'standard' par défaut)

show_pv_pvc() {
    cat <<'EOF'
# ── PersistentVolume (admin crée la capacité) ────────────────────
apiVersion: v1
kind: PersistentVolume
metadata:
  name: techshop-pv-data
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce       # monté en lecture/écriture par 1 seul nœud
    # ReadOnlyMany        # monté en lecture par plusieurs nœuds
    # ReadWriteMany       # monté en R/W par plusieurs nœuds
  persistenceReclaimPolicy: Retain   # Retain | Recycle | Delete
  storageClassName: standard
  hostPath:
    path: /mnt/data/techshop          # chemin sur le nœud (dev uniquement)

---
# ── PersistentVolumeClaim (développeur demande du stockage) ──────
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: techshop-pvc-data
  namespace: techshop-dev
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard
  resources:
    requests:
      storage: 2Gi    # doit être <= capacité du PV

---
# ── Utilisation dans un Pod/Deployment ──────────────────────────
# Dans la spec du container :
#   volumeMounts:
#     - name: data-volume
#       mountPath: /app/data
# Dans la spec du Pod :
#   volumes:
#     - name: data-volume
#       persistentVolumeClaim:
#         claimName: techshop-pvc-data
EOF

    # Commandes
    kubectl get pv                          # lister les PersistentVolumes
    kubectl get pvc -n techshop-dev         # lister les PVCs
    kubectl describe pvc techshop-pvc-data  # détails d'un PVC
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6 : CONFIGMAP
# ─────────────────────────────────────────────────────────────────────────────
# Stocker des configurations non sensibles (fichiers de config, variables d'env)

show_configmap() {
    cat <<'EOF'
# ── ConfigMap — variables d'environnement ────────────────────────
apiVersion: v1
kind: ConfigMap
metadata:
  name: techshop-config
  namespace: techshop-dev
data:
  APP_ENV: "development"
  DB_HOST: "mysql-service"
  DB_PORT: "3306"
  DB_NAME: "techshop"
  LOG_LEVEL: "INFO"
  prometheus.yml: |
    global:
      scrape_interval: 15s
    scrape_configs:
      - job_name: 'techshop-api'
        static_configs:
          - targets: ['api-service:8000']

---
# ── Injection dans un Deployment (env vars) ──────────────────────
# Dans spec.containers :
#   envFrom:
#     - configMapRef:
#         name: techshop-config
#
# Ou variable individuelle :
#   env:
#     - name: APP_ENV
#       valueFrom:
#         configMapKeyRef:
#           name: techshop-config
#           key: APP_ENV
#
# ── Injection comme fichier (volume) ─────────────────────────────
# volumes:
#   - name: config-volume
#     configMap:
#       name: techshop-config
# volumeMounts:
#   - name: config-volume
#     mountPath: /etc/config
EOF

    # Commandes
    kubectl get configmap -n techshop-dev
    kubectl describe configmap techshop-config -n techshop-dev
    # Créer depuis fichier
    kubectl create configmap app-config --from-file=prometheus.yml -n techshop-dev
    # Créer depuis variables
    kubectl create configmap db-config --from-literal=DB_HOST=mysql --from-literal=DB_PORT=3306
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7 : SECRET
# ─────────────────────────────────────────────────────────────────────────────
# Comme ConfigMap mais pour les données sensibles (encodé Base64, pas chiffré !)

show_secrets() {
    cat <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: techshop-secrets
  namespace: techshop-dev
type: Opaque
data:
  DB_PASSWORD: bW90ZGVwYXNzZQ==     # echo -n "motdepasse" | base64
  API_KEY: c2VjcmV0a2V5MTIz

# Ou en stringData (automatiquement encodé par K8s) :
stringData:
  DB_PASSWORD: "motdepasse"
  API_KEY: "secretkey123"
EOF

    # Créer depuis commande
    kubectl create secret generic techshop-secrets \
        --from-literal=DB_PASSWORD=motdepasse \
        --from-literal=API_KEY=secretkey123 \
        -n techshop-dev
    kubectl get secret techshop-secrets -o jsonpath='{.data.DB_PASSWORD}'
    # # Returns the secret string encoded in base64
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8 : SERVICE
# ─────────────────────────────────────────────────────────────────────────────
# Expose les Pods via une IP stable et un DNS interne.
# Types : ClusterIP | NodePort | LoadBalancer

show_services() {
    cat <<'EOF'
# ── ClusterIP (par défaut) — accès interne uniquement ────────────
apiVersion: v1
kind: Service
metadata:
  name: api-service
  namespace: techshop-dev
spec:
  selector:
    app: techshop-api    # cible les Pods avec ce label
  ports:
    - protocol: TCP
      port: 80           # port du service (accessible via api-service:80)
      targetPort: 8000   # port du container
  type: ClusterIP

---
# ── NodePort — accès depuis l'extérieur via l'IP du nœud ─────────
apiVersion: v1
kind: Service
metadata:
  name: api-nodeport
  namespace: techshop-dev
spec:
  selector:
    app: techshop-api
  ports:
    - port: 80
      targetPort: 8000
      nodePort: 30080    # plage 30000-32767, accessible sur IP_NOEUD:30080
  type: NodePort

---
# ── LoadBalancer — pour les clouds (minikube : minikube tunnel) ──
apiVersion: v1
kind: Service
metadata:
  name: api-lb
  namespace: techshop-dev
spec:
  selector:
    app: techshop-api
  ports:
    - port: 80
      targetPort: 8000
  type: LoadBalancer
EOF

    # Commandes
    kubectl get services -n techshop-dev
    kubectl get svc -n techshop-dev
    kubectl describe service api-service -n techshop-dev
    # Accéder au service depuis minikube
    minikube service api-nodeport -n techshop-dev --url
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 9 : DEPLOYMENT
# ─────────────────────────────────────────────────────────────────────────────
# Gère le nombre de réplicas, les rolling updates, les rollbacks.

show_deployment() {
    cat <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: techshop-api
  namespace: techshop-dev
  labels:
    app: techshop-api
spec:
  replicas: 2                       # nombre de Pods

  selector:
    matchLabels:
      app: techshop-api             # doit correspondre aux labels du template

  strategy:
    type: RollingUpdate             # mise à jour sans interruption
    rollingUpdate:
      maxSurge: 1                   # +1 Pod pendant le déploiement
      maxUnavailable: 0             # 0 Pod indisponible (zero-downtime)

  template:
    metadata:
      labels:
        app: techshop-api           # label ciblé par le Service
    spec:
      containers:
        - name: api
          image: moncompte/techshop-api:v1.2.0
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8000

          # Variables d'environnement depuis ConfigMap + Secret
          envFrom:
            - configMapRef:
                name: techshop-config
            - secretRef:
                name: techshop-secrets

          # Montage d'un volume
          volumeMounts:
            - name: data-vol
              mountPath: /app/data
            - name: prometheus-config
              mountPath: /etc/prometheus

          # Ressources (bonnes pratiques en prod)
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"

          # Health checks
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 15

          readinessProbe:
            httpGet:
              path: /ready
              port: 8000
            initialDelaySeconds: 5
            periodSeconds: 10

      volumes:
        - name: data-vol
          persistentVolumeClaim:
            claimName: techshop-pvc-data
        - name: prometheus-config
          configMap:
            name: techshop-config
            items:
              - key: prometheus.yml
                path: prometheus.yml
EOF

    # Commandes
    kubectl apply -f deployment.yaml               # créer/mettre à jour
    kubectl get deployments -n techshop-dev        # lister
    kubectl describe deployment techshop-api -n techshop-dev
    kubectl get pods -n techshop-dev -l app=techshop-api   # pods du deployment
    kubectl logs -n techshop-dev -l app=techshop-api       # logs
    kubectl exec -it -n techshop-dev POD_NAME -- /bin/bash  # shell dans un pod

    # Mise à jour de l'image
    kubectl set image deployment/techshop-api api=moncompte/techshop-api:v1.3.0 -n techshop-dev
    kubectl rollout status deployment/techshop-api -n techshop-dev
    kubectl rollout history deployment/techshop-api -n techshop-dev
    kubectl rollout undo deployment/techshop-api -n techshop-dev   # rollback

    # Scaler
    kubectl scale deployment techshop-api --replicas=4 -n techshop-dev
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 10 : DÉPLOIEMENT COMPLET TECHSHOP (exemple pratique)
# ─────────────────────────────────────────────────────────────────────────────

deploy_techshop_demo() {
    NS="techshop-dev"
    kubectl create namespace ${NS} --dry-run=client -o yaml | kubectl apply -f -

    # ConfigMap
    kubectl create configmap techshop-config \
        --from-literal=APP_ENV=development \
        --from-literal=DB_HOST=mysql-service \
        --from-literal=DB_PORT=3306 \
        -n ${NS} --dry-run=client -o yaml | kubectl apply -f -

    # Secret
    kubectl create secret generic techshop-secrets \
        --from-literal=DB_PASSWORD=motdepasse \
        --from-literal=DB_ROOT_PASSWORD=rootpwd \
        -n ${NS} --dry-run=client -o yaml | kubectl apply -f -

    # Voir toutes les ressources
    kubectl get all -n ${NS}
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 11 : COMMANDES KUBECTL ESSENTIELLES
# ─────────────────────────────────────────────────────────────────────────────

kubectl_cheatsheet() {
    cat <<'EOF'
# ── Inspection ───────────────────────────────────────────────────
kubectl get all -n MON_NS                   # toutes les ressources
kubectl get pods -n MON_NS -o wide          # pods avec plus de détails
kubectl get pod MON_POD -o yaml             # YAML complet d'une ressource
kubectl describe pod MON_POD -n MON_NS      # description détaillée
kubectl top pods -n MON_NS                  # consommation CPU/RAM (si metrics-server actif)

# ── Logs ─────────────────────────────────────────────────────────
kubectl logs MON_POD -n MON_NS              # logs du pod
kubectl logs MON_POD -n MON_NS -f           # suivre en temps réel
kubectl logs MON_POD -n MON_NS --previous   # logs du pod précédent (si crash)
kubectl logs -l app=techshop-api -n MON_NS  # logs de tous les pods du label

# ── Exécution ────────────────────────────────────────────────────
kubectl exec -it MON_POD -n MON_NS -- bash          # shell interactif
kubectl exec MON_POD -n MON_NS -- ls /app            # commande one-shot
kubectl port-forward pod/MON_POD 8080:8000 -n MON_NS # rediriger port local

# ── Gestion ──────────────────────────────────────────────────────
kubectl apply -f fichier.yaml               # créer/mettre à jour
kubectl delete -f fichier.yaml              # supprimer via YAML
kubectl delete pod MON_POD -n MON_NS        # supprimer un pod (sera recréé par deployment)
kubectl delete deployment MON_DEP -n MON_NS # supprimer un deployment

# ── Contexte / Config ────────────────────────────────────────────
kubectl config get-contexts                 # lister les contextes
kubectl config use-context minikube         # changer de contexte
kubectl config current-context             # contexte actif

# ── Dry-run (valider sans appliquer) ─────────────────────────────
kubectl apply -f fichier.yaml --dry-run=client
kubectl create deployment test --image=nginx --dry-run=client -o yaml
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# POINT D'ENTRÉE
# ─────────────────────────────────────────────────────────────────────────────

echo "=================================================="
echo " Fiche Kubernetes dev — nœud unique (minikube)"
echo " Fonctions disponibles :"
echo "   install_kubectl        → installer kubectl"
echo "   install_minikube       → installer minikube"
echo "   start_minikube         → démarrer le cluster"
echo "   kubectl_namespaces     → gestion namespaces"
echo "   show_pv_pvc            → PersistentVolume / Claim"
echo "   show_configmap         → ConfigMap"
echo "   show_secrets           → Secrets"
echo "   show_services          → Services"
echo "   show_deployment        → Deployment complet"
echo "   kubectl_cheatsheet     → commandes essentielles"
echo "   show_probes            → liveness / readiness / startup probes"
echo "=================================================="



# ─────────────────────────────────────────────────────────────────────────────
# SECTION 12 : STATEFULSET
# ─────────────────────────────────────────────────────────────────────────────

show_statefulset() {
  cat << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mariadb
spec:
  selector:
    matchLabels:
      app: mariadb
  serviceName: mariadb
  replicas: 1
  template:
    metadata:
      labels:
        app: mariadb
    spec:
      containers:
        - name: mariadb
          image: docker.io/mariadb:10.4
          ports:
            - containerPort: 3306
              protocol: TCP
          env:
            - name: MARIADB_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mariadb-root-password
                  key: password
          envFrom:
            - secretRef:
                name: mariadb-user
          volumeMounts:
            - name: data
              mountPath: /var/lib/mysql
            - name: config
              mountPath: etc/mysql/conf.d

      volumes:
        - emptyDir: {}
          name: data
        - name: config
          configMap:
            name: cm-mariadb
            items:
              - key: mysqld.cnf
                path: mysqld.cnf
EOF
}
# ─────────────────────────────────────────────────────────────────────────────
# SECTION 13 : PROBES — LIVENESS, READINESS (et STARTUP)
# ─────────────────────────────────────────────────────────────────────────────
# Les probes sont des health checks exécutés par le kubelet sur chaque container.
#
#   livenessProbe  : "le container est-il VIVANT ?"
#                    → en échec : le kubelet REDÉMARRE le container
#                    → sert à sortir d'un deadlock / d'une app figée
#
#   readinessProbe : "le container est-il PRÊT à recevoir du trafic ?"
#                    → en échec : le Pod est RETIRÉ des endpoints du Service
#                      (plus de trafic), mais il n'est PAS redémarré
#                    → sert au démarrage (chargement modèle ML, connexion DB)
#                      et pendant les rolling updates (zero-downtime)
#
#   startupProbe   : "le container a-t-il fini de DÉMARRER ?"
#                    → tant qu'elle n'a pas réussi, liveness et readiness
#                      sont désactivées (évite de tuer une app lente à démarrer)
#
# 3 mécanismes de test : httpGet (code 200-399) | tcpSocket (port ouvert)
#                        | exec (commande qui renvoie 0) | grpc
#
# Paramètres communs :
#   initialDelaySeconds : attente avant la 1re probe          (défaut 0)
#   periodSeconds       : intervalle entre deux probes        (défaut 10)
#   timeoutSeconds      : délai max de réponse                (défaut 1)
#   failureThreshold    : nb d'échecs consécutifs → "KO"      (défaut 3)
#   successThreshold    : nb de succès consécutifs → "OK"     (défaut 1,
#                         doit valoir 1 pour liveness/startup)
#
# Piège classique : une liveness qui vérifie la DB → si la DB tombe, TOUS les
# pods de l'API redémarrent en boucle. La liveness doit tester le process
# lui-même ; les dépendances (DB, cache…) vont dans la readiness.

show_probes() {
    cat <<'EOF'
# ── Exemple 1 : API HTTP (FastAPI) — probes httpGet ─────────────
apiVersion: apps/v1
kind: Deployment
metadata:
  name: techshop-api
  namespace: techshop-dev
spec:
  replicas: 2
  selector:
    matchLabels:
      app: techshop-api
  template:
    metadata:
      labels:
        app: techshop-api
    spec:
      containers:
        - name: api
          image: moncompte/techshop-api:v1.2.0
          ports:
            - name: http              # port nommé, réutilisable dans les probes
              containerPort: 8000

          # Liveness : /health répond 200 si le process tourne (pas de check DB !)
          livenessProbe:
            httpGet:
              path: /health
              port: http              # ou 8000
            initialDelaySeconds: 15   # laisser le temps à uvicorn de démarrer
            periodSeconds: 20         # vérifier toutes les 20 s
            timeoutSeconds: 2         # réponse attendue en moins de 2 s
            failureThreshold: 3       # 3 échecs (≈ 60 s) → redémarrage

          # Readiness : /ready répond 200 seulement si DB joignable + modèle chargé
          readinessProbe:
            httpGet:
              path: /ready
              port: http
              httpHeaders:            # en-têtes optionnels
                - name: X-Probe
                  value: readiness
            initialDelaySeconds: 5
            periodSeconds: 5          # plus fréquente : réagit vite aux pannes
            timeoutSeconds: 2
            failureThreshold: 2       # 2 échecs → retiré du Service
            successThreshold: 1       # 1 succès → remis dans le Service

# Côté code FastAPI, par exemple :
#   @app.get("/health")
#   def health(): return {"status": "alive"}
#
#   @app.get("/ready")
#   def ready():
#       if model is None or not db_ok():
#           raise HTTPException(status_code=503)   # 503 → probe en échec
#       return {"status": "ready"}

---
# ── Exemple 2 : app ML lente à démarrer — startupProbe ──────────
# Le modèle met jusqu'à 5 min à se charger : sans startupProbe, la liveness
# tuerait le container avant la fin du chargement (boucle CrashLoopBackOff).
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ml-model-api
  namespace: techshop-dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ml-model-api
  template:
    metadata:
      labels:
        app: ml-model-api
    spec:
      containers:
        - name: model
          image: moncompte/ml-model-api:v2.0.0
          ports:
            - containerPort: 8080

          # Startup : jusqu'à 30 × 10 s = 300 s pour démarrer
          startupProbe:
            httpGet:
              path: /health
              port: 8080
            periodSeconds: 10
            failureThreshold: 30

          # Liveness : active seulement APRÈS le succès de la startupProbe
          # (donc pas besoin d'initialDelaySeconds)
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            periodSeconds: 15
            failureThreshold: 3

          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            periodSeconds: 5
            failureThreshold: 3

---
# ── Exemple 3 : base de données — tcpSocket + exec ──────────────
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mariadb
  namespace: techshop-dev
spec:
  serviceName: mariadb
  replicas: 1
  selector:
    matchLabels:
      app: mariadb
  template:
    metadata:
      labels:
        app: mariadb
    spec:
      containers:
        - name: mariadb
          image: docker.io/mariadb:10.4
          ports:
            - containerPort: 3306
          env:
            - name: MARIADB_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mariadb-root-password
                  key: password

          # Liveness TCP : le port 3306 accepte-t-il les connexions ?
          livenessProbe:
            tcpSocket:
              port: 3306
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 3

          # Readiness exec : la commande doit renvoyer le code 0
          # (ici : le serveur répond réellement à une requête SQL)
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - mysqladmin ping -uroot -p"$MARIADB_ROOT_PASSWORD"
            initialDelaySeconds: 10
            periodSeconds: 5
            timeoutSeconds: 3

---
# ── Exemple 4 : démo pédagogique — voir la liveness redémarrer ──
# Le container crée /tmp/healthy, puis le supprime après 30 s.
# → la liveness (cat /tmp/healthy) échoue → redémarrage (RESTARTS augmente)
apiVersion: v1
kind: Pod
metadata:
  name: liveness-demo
  namespace: techshop-dev
spec:
  containers:
    - name: demo
      image: busybox:1.36
      args:
        - /bin/sh
        - -c
        - touch /tmp/healthy; sleep 30; rm -f /tmp/healthy; sleep 600
      livenessProbe:
        exec:
          command: ["cat", "/tmp/healthy"]
        initialDelaySeconds: 5
        periodSeconds: 5
EOF

    # Commandes utiles pour observer / déboguer les probes
    kubectl apply -f probes.yaml
    kubectl get pods -n techshop-dev -w                    # READY 0/1 = readiness KO, RESTARTS = liveness KO
    kubectl describe pod liveness-demo -n techshop-dev     # section Events : "Liveness probe failed ..."
    kubectl get events -n techshop-dev --field-selector reason=Unhealthy
    kubectl get endpoints api-service -n techshop-dev      # pods "ready" derrière le Service
    kubectl logs POD_NAME -n techshop-dev --previous       # logs avant le dernier redémarrage
}

# ─────────────────────────────────────────────────────────────────────────────
# Lancement : ./09_kubernetes.sh <fonction>   (sans argument : liste des fonctions)
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ $# -eq 0 ]]; then
        echo "Usage : $0 <fonction>"; declare -F | awk '{print "  - " $3}'
    else
        "$@"
    fi
fi
