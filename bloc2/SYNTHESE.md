# Bloc 2 — Synthèse : architecture, choix techniques, pistes d'amélioration

## 1. Contexte et objectif

- **Données** : `orders.json` (179 Mo), 180 519 lignes de commande d'une enseigne de sport,
  janvier 2015 → janvier 2018, au format JSON imbriqué.
- **Objectif** : construire une chaîne complète *données brutes → base relationnelle → modèle ML*.
- **Cas d'usage ML** : signaler au moment de la commande celles qui risquent d'être des fraudes
  (statut `SUSPECTED_FRAUD`).

## 2. Architecture

```
orders.json ──► etl.py ──► data/processed/orders_clean.csv ──► ingestion.py ──► Base SQL ──► train.py ──► models/
  (brut)      extract +       (fichier plat, propre)           découpe en      (SQLite ou     requête       fraud_model.joblib
              transform                                         5 tables        MySQL)         agrégée        metrics.json
                                                                   ▲
                                                           create_db.py (schéma ORM)
```

| Fichier | Rôle |
|---|---|
| `01_exploration.ipynb` | Exploration : structure, qualité, distributions, cible ML → décisions |
| `config.py` | Chemins, `DATABASE_URL` (variables d'environnement / `.env`), logger commun |
| `etl.py` | Extraction du JSON, aplatissement, nettoyage, règles qualité, écriture CSV |
| `create_db.py` | Modèles SQLAlchemy (ORM) et création des tables |
| `ingestion.py` | Découpage en entités et chargement transactionnel, vérification des volumes |
| `train.py` | Features, découpage temporel, comparaison de modèles, évaluation, sauvegarde |
| `docker-compose.yml` | MySQL + phpMyAdmin (optionnel) |

**Exécution :**
```bash
pip install -r requirements.txt
python etl.py          # ~8 s
python create_db.py    # crée les tables (--reset pour repartir de zéro)
python ingestion.py    # ~5 s
python train.py        # ~10 s
```

### Modèle de données (3e forme normale)

```
categories (id PK, name)
    1
    │
    n
products (id PK, name UNIQUE, price, category_id FK)
    1
    │
    n
order_items (id PK, order_id FK, product_id FK, quantity, unit_price, sales)
    n
    │
    1
orders (id PK, customer_id FK, order_date, shipping_date, payment_type, status, market,
        country, state, region, city)          ← lieu de LIVRAISON
    n
    │
    1
customers (id PK, firstname, lastname, street, city, state, zipcode, country)  ← adresse CLIENT
```

Volumes chargés : 51 catégories, 118 produits, 20 652 clients, 65 752 commandes, 169 149 lignes.

## 3. Choix techniques

### Exploration → ETL
| Constat (notebook) | Choix |
|---|---|
| JSON imbriqué (`loc`, `product`, `customer.loc`) | `pd.json_normalize`, colonnes renommées en snake_case |
| `order zipcode` absent à 86 % | colonne supprimée (imputer 86 % n'aurait pas de sens) |
| 8 `lastname` et 3 `zipcode` manquants | `"Inconnu"` / `NULL` ; zipcode `725.0` → texte `"00725"` |
| 11 370 doublons stricts, pas de clé de ligne | supprimés (choix assumé, documenté) |
| Espaces parasites (`"Smart watch "`) | `str.strip()` sur toutes les chaînes |
| Données cohérentes aujourd'hui | règles codées quand même dans `validate()` (montant = qté × prix, dates, en-tête constant par commande) pour protéger les chargements futurs |

- **CSV intermédiaire** : découple ETL et ingestion (on peut relancer l'un sans l'autre,
  et inspecter le résultat). Parquet serait plus efficace (typage conservé, compression).
- **Logging** plutôt que `print`, **argparse** pour les chemins, **erreurs explicites**
  (fichier absent, colonnes manquantes).

### Base de données
- **SQLAlchemy 2.0 ORM** (style `Mapped[...]` / `mapped_column`) : schéma en Python, indépendant
  du SGBD, relations navigables (`order.items`, `product.category`).
- **SQLite par défaut** (aucune installation), **MySQL** en changeant seulement `DATABASE_URL`
  — les secrets restent dans `.env`, jamais dans le code.
- **3FN** : chaque information est stockée une seule fois (un client, un produit, une
  catégorie) → pas d'anomalies de mise à jour.
- `id` de la source = id de **commande** (pas de ligne) → séparation `orders` / `order_items`.
- Adresse du client ≠ lieu de livraison → colonnes distinctes (clients tous aux US/Porto Rico,
  livraisons dans 5 marchés).
- `unit_price` copié dans `order_items` : le prix au moment de la commande ne doit pas changer
  si le catalogue évolue.
- **Contraintes** : clés étrangères, `UNIQUE` sur le nom produit, `CHECK` (prix > 0, quantité > 0),
  index sur les clés étrangères, la date et le statut (colonnes filtrées/jointes).

### Ingestion
- **Une seule transaction** (`session.begin()`) : tout ou rien, rollback en cas d'erreur.
- **Idempotente** : vidage puis rechargement → relançable sans doublons.
- **Insertion par lots** (`insert(Model)` + liste de dicts, lots de 10 000) : ~100× plus rapide
  que des `session.add()` unitaires.
- Ordre imposé par les clés étrangères (parents d'abord ; suppression dans l'ordre inverse).
- **Contrôle post-chargement** : comptage en base = comptage attendu.

### Machine Learning
- **Granularité commande** : agrégation SQL (nb lignes, quantité, montant, nb catégories…).
- **Pas de fuite de données** : le statut sert uniquement à fabriquer la cible ; la date
  d'expédition est exclue (inconnue au moment de la commande).
- **Découpage temporel** (train < 01/07/2017, test après) : simule la production, où l'on
  prédit le futur à partir du passé. Un découpage aléatoire serait trop optimiste.
- **Classe rare (2,26 %)** : `class_weight="balanced"`, métrique principale **PR-AUC**
  (l'accuracy serait de 97,7 % en prédisant toujours « pas fraude »).
- **Pipeline scikit-learn** (`ColumnTransformer` : OneHotEncoder + StandardScaler, puis
  classifieur) : le prétraitement est appris sur le train uniquement et sauvegardé avec le
  modèle → mêmes transformations en production.
- **Comparaison** en validation croisée stratifiée 5 plis : Dummy (référence), régression
  logistique, Random Forest.

**Résultats (jeu de test, 13 670 commandes) :**

| Modèle | PR-AUC CV | |
|---|---|---|
| Dummy (référence) | 0,023 | |
| Régression logistique | 0,081 | |
| **Random Forest** (retenu) | **0,084** | test : ROC-AUC 0,88, PR-AUC 0,094 |

Au seuil 0,5 : **rappel fraude 96 %** (296/308) mais **précision 8 %** (3 281 fausses alertes).

**Interprétation honnête** : le modèle a essentiellement appris la règle « paiement
`TRANSFER` → risque » (100 % des fraudes sont des virements, 8 % des virements sont des
fraudes). Les autres variables n'apportent presque rien : dans ce jeu de données, la fraude
semble **aléatoire au sein des virements**. Le modèle sert donc de **filtre de priorisation**
(on ne contrôle que ~25 % des commandes pour attraper 96 % des fraudes), pas de détecteur précis.

## 4. Pistes d'amélioration

**Données / ETL**
- Remplacer le CSV par **Parquet** ; lire le JSON en flux (`ijson`) pour les gros volumes.
- **Chargement incrémental** (upsert sur les nouvelles commandes) au lieu du rechargement complet.
- Validation déclarative du schéma (**Pydantic**, **Pandera**, Great Expectations) et rapport
  qualité à chaque exécution ; mise en quarantaine des lignes rejetées.
- Tables de référence pour les lieux (pays/région/ville) et normalisation des libellés
  (`"EE. UU."` → `"United States"`).

**Base de données**
- Migrations de schéma avec **Alembic** au lieu de `create_all`.
- Utilisateur SQL à droits restreints pour l'application, sauvegardes, secrets via un coffre.

**Machine Learning**
- **Features comportementales** : historique du client (nb de commandes passées, ancienneté,
  fraudes antérieures, changement d'adresse), écart lieu de livraison / adresse client,
  vitesse de commande.
- **Ajuster le seuil** selon le coût métier (coût d'un contrôle vs coût d'une fraude ratée)
  plutôt que 0,5 ; courbe précision/rappel.
- Optimisation des hyperparamètres (`GridSearchCV` / Optuna avec `TimeSeriesSplit`),
  essai de gradient boosting (LightGBM, `HistGradientBoostingClassifier`).
- Interprétabilité (importance par permutation, SHAP) pour justifier les alertes.
- **Suivi des expériences** (MLflow), versionnement des données/modèles (DVC).

**Industrialisation**
- **Tests** (pytest) : fonctions de transformation, règles de validation, ingestion sur une base
  SQLite en mémoire.
- **Orchestration** (Airflow, Prefect, ou simple cron) : ETL → ingestion → entraînement.
- **API de prédiction** (FastAPI) chargeant `fraud_model.joblib`, conteneurisée avec Docker.
- **CI/CD** (GitLab CI) : lint, tests, build d'image ; **monitoring** de la dérive des données
  et des performances en production.
- **Sobriété** : SQLite/modèles légers suffisent ici ; éviter de réentraîner sans nouvelles données.
