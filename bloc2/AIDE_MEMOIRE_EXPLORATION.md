# Aide-mémoire — Les étapes de l'exploration de données

> **Objectif** : comprendre les données **avant** de coder l'ETL ou le modèle.
> Chaque constat doit déboucher sur une **décision** (nettoyer, supprimer, imputer, typer,
> structurer la base, choisir une métrique…).
>
> Deux exemples complets servent de fil rouge :
> - **orders.json** (commandes) : `bloc2/01_exploration.ipynb` ;
> - **extract_async.json** (salaires GAFAM « Stonewindow », sujet d'examen) :
>   `bloc2_correction/exploration.ipynb` et `etl.py`. Ses transformations sont détaillées
>   dans la partie **« Transformations de la correction »**.
>
> Les extraits ont été testés avec l'environnement `exam_bloc2` (Python 3.12, **pandas 3.1**).

```python
import json
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns
```

---

## Vue d'ensemble

| # | Étape | Question posée | Exemple orders.json | Exemple correction (Stonewindow) |
|---|---|---|---|---|
| 1 | Charger et observer la structure | À quoi ressemble une ligne ? | JSON imbriqué → `json_normalize` | clé racine `employees`, 4 blocs imbriqués |
| 2 | Aplatir et typer | Les types sont-ils bons ? | dates en texte → `to_datetime` | `flatten` maison avec `_` et `clé*` |
| 3 | Valeurs manquantes | Où ? Combien ? Pourquoi ? | 86 % manquant → colonne supprimée | `""` déguisés → `None` ; 2 063 hors périmètre |
| 4 | Doublons et granularité | Que représente une ligne ? | `id` = commande → `orders` + `order_items` | une ligne = un employé ; doublons sur `id` |
| 5 | Cohérence / règles métier | Les données sont-elles logiques ? | règles dans `validate()` | expérience > âge − 14 → `None` |
| 6 | Analyse univariée | Comment chaque variable est-elle distribuée ? | asymétrie, valeurs rares | âges négatifs, salaire = 0, genre en 6 écritures |
| 7 | Analyse bivariée | Quelles variables sont liées ? | fraude liée à `TRANSFER` | salaire selon `position_level` |
| 8 | Analyse temporelle | Comment ça évolue dans le temps ? | 2018 partiel → découpage temporel | 2 formats de date dans une colonne |
| 9 | Cible ML | Que prédire ? Avec quoi ? | classes déséquilibrées → PR-AUC | régression du salaire → MAE / RMSE / R² |
| 10 | Synthèse des décisions | Qu'en fait-on ? | tableau constat → décision → fichier | tableau du `README.md` |

---

## 1. Charger et observer la structure

```python
with open("orders.json", encoding="utf-8") as f:
    records = json.load(f)

type(records), len(records)                          # liste ? combien d'éléments ?
print(json.dumps(records[0], indent=2, ensure_ascii=False))   # une ligne lisible
```
- Repérer les **objets imbriqués** (`loc`, `product`, `customer.loc`) et les listes.
- Vérifier que **toutes les clés sont présentes partout** : une clé absente devient une
  valeur manquante après aplatissement.

## 2. Aplatir et typer

```python
df = pd.json_normalize(records)          # "product.name", "customer.loc.city"...
df.shape                                 # (lignes, colonnes)
df.head()
df.dtypes                                # object = texte (ou mélange !)
df.info()                                # types + nombre de non-nuls
df.describe()                            # stats des colonnes numériques
df.describe(include="object")            # count / unique / top / freq des textes
```
- Dates en `object` → `pd.to_datetime` (voir la section « Dates » plus bas).
- Codes postaux, identifiants : à stocker **en texte** (`725.0` → `"00725"`), même s'ils
  ressemblent à des nombres. On ne fait pas de calcul dessus et les zéros de tête comptent.
- Colonnes catégorielles à peu de valeurs : `astype("category")` économise la mémoire.

## 3. Valeurs manquantes

```python
manquants = pd.DataFrame({
    "nb": df.isna().sum(),
    "%": df.isna().mean().mul(100).round(3),
})
manquants[manquants["nb"] > 0].sort_values("nb", ascending=False)

df[df["customer.lastname"].isna()]       # regarder les lignes concernées
```
**Décider selon le taux et le sens métier :**

| Situation | Décision type |
|---|---|
| Colonne majoritairement vide (> 50-70 %) | supprimer la colonne |
| Quelques lignes, champ non essentiel | imputer (`"Inconnu"`, médiane, mode) ou laisser `NULL` |
| Champ obligatoire (id, date, montant) | rejeter la ligne et la tracer dans les logs |
| Le manque a un sens (« pas de remise ») | créer une modalité / un indicateur `is_missing` |

> Attention : `0`, `""`, `"N/A"`, `-1` ou `"?"` sont souvent des manquants **déguisés**.
> Utiliser `df[col].value_counts()` pour les repérer, et `na_values=[...]` à la lecture d'un CSV.


### drop de colonnes
```
df = df.drop(columns=df.columns[[0, 2]])
```


## 4. Doublons et granularité

```python
df.duplicated().sum()                    # doublons stricts (toutes colonnes)
df.duplicated(subset=["id", "product.name"]).sum()   # doublons sur une clé
df["id"].is_unique                       # l'id identifie-t-il une ligne ?
df["id"].nunique(), df["customer.id"].nunique(), df["product.name"].nunique()
```
- **Granularité** : savoir ce que représente une ligne. Ici une **ligne de commande**, pas
  une commande → c'est ce qui justifie le modèle relationnel (`orders` + `order_items`).
- Compter les entités distinctes (clients, produits, catégories) prépare la **normalisation** de la base.

## 5. Cohérence et règles métier

```python
# Montant = quantité x prix ?
(df["sales"] - df["quantity"] * df["product.price"]).abs().gt(0.01).sum()
# Valeurs impossibles
(df["quantity"] <= 0).sum(), (df["product.price"] <= 0).sum()
# Attributs d'en-tête constants au sein d'une commande ?
(df.groupby("id")[["customer.id", "status", "date order"]].nunique() > 1).sum()
# Un prix par produit ?
(df.groupby("product.name")["product.price"].nunique() > 1).sum()
# Espaces parasites, casse
(df["product.name"] != df["product.name"].str.strip()).sum()
df["market"].str.lower().value_counts()
```
Même si tout est cohérent aujourd'hui, **coder ces règles dans l'ETL** protège les chargements futurs.

## 6. Analyse univariée

```python
# Catégorielles : effectifs et proportions
df["status"].value_counts()
df["status"].value_counts(normalize=True)
df["status"].value_counts().plot.barh()

# Numériques : distribution, asymétrie, valeurs extrêmes
df["sales"].describe()
df["sales"].skew()                       # > 1 : forte asymétrie à droite
sns.histplot(df["sales"], bins=50)
sns.boxplot(x=df["sales"])

# Valeurs aberrantes (règle de l'IQR)
q1, q3 = df["sales"].quantile([0.25, 0.75])
iqr = q3 - q1
outliers = df[(df["sales"] < q1 - 1.5 * iqr) | (df["sales"] > q3 + 1.5 * iqr)]
```
Une valeur aberrante n'est pas forcément une erreur (produit cher, grosse commande) : **vérifier avant de supprimer**.

## 7. Analyse bivariée

```python
# Catégorielle x catégorielle
pd.crosstab(df["type"], df["status"], normalize="index")
# Numérique selon une catégorie
df.groupby("market")["sales"].agg(["mean", "median", "sum"])
sns.boxplot(data=df, x="market", y="sales")
# Numérique x numérique
df.select_dtypes("number").corr()
sns.heatmap(df.select_dtypes("number").corr(), annot=True, cmap="coolwarm")
# Taux de la cible par modalité (très parlant)
df.assign(fraude=df["status"].eq("SUSPECTED_FRAUD")).groupby("type")["fraude"].mean()
```
Corrélation ≠ causalité. Une corrélation **trop** forte avec la cible doit faire penser à une
**fuite de données** (variable connue seulement après coup).

## 8. Analyse temporelle

```python
ca_mensuel = df.set_index("date order")["sales"].resample("MS").sum()
ca_mensuel.plot(title="CA mensuel")
df.groupby(df["date order"].dt.year)["id"].nunique()     # commandes par an
df["date order"].min(), df["date order"].max()           # période couverte
```
Chercher : tendance, saisonnalité, ruptures, **périodes incomplètes** (janvier 2018 ici).
Les détails sur les dates sont dans la section suivante.

## 9. Préparer la problématique ML

- **Cible** : la définir clairement (ici `is_fraud = status == "SUSPECTED_FRAUD"`) et se placer à la
  bonne granularité (une ligne = une commande).
- **Équilibre des classes** : `y.value_counts(normalize=True)` → si déséquilibre, l'accuracy est
  trompeuse ; préférer précision / rappel / F1 / PR-AUC, et `class_weight="balanced"`.
- **Fuite de données** : exclure tout ce qui n'est pas connu au moment de la prédiction
  (le statut, la date d'expédition…).
- **Découpage** : temporel si les données évoluent dans le temps (on apprend sur le passé, on teste sur le futur).
- **Baseline** : toujours comparer à un modèle naïf (`DummyClassifier`).

## 10. Synthèse des décisions

Terminer par un tableau **Constat → Décision → Où** (voir la fin de `01_exploration.ipynb`).
C'est ce qui justifie à l'oral chaque ligne de l'ETL, du schéma de base et du modèle.

---

## Transformations de la correction (bloc2_correction, Stonewindow)

Le fichier `extract_async.json` contient 50 000 employés. Chacun a un `id` et 4 blocs imbriqués :
`personal`, `company`, `job`, `experience`. Chaque transformation est montrée **deux fois** :
- en version **pandas** (colonne entière), comme dans le notebook d'exploration ;
- en version **ligne par ligne** (fonctions Python pures), comme dans `etl.py`. C'est celle
  qu'utilise l'ingestion : une ligne invalide est loguée et ignorée **sans arrêter** le chargement.

| # | Problème repéré | Ampleur | Transformation |
|---|---|---|---|
| T1 | Fichier à télécharger depuis S3 | 64 Mo | `requests` + `raise_for_status()` |
| T2 | Liste dans une clé racine `employees` | — | contrôle du format puis `data["employees"]` |
| T3 | JSON imbriqué, clés parfois absentes | 4 blocs | `flatten` maison (`_`, `None`, `clé*`) |
| T4 | Personnes sans entreprise / poste / expérience | 2 063 | hors périmètre : retirées de l'analyse |
| T5 | Chaînes vides = manquants déguisés | `email` 7 252, `education_level` 2 420, `marital_status` 2 386 | `""` → `None` |
| T6 | Genre écrit de 6 façons | `M`, `Male`, `male`, `F`… | dictionnaire → `M` / `F` |
| T7 | Âge et expérience négatifs | miroir des valeurs positives | erreur de signe → `abs()` |
| T8 | Salaire à 0 | 2 405 | `0` → `None` (inconnu, pas « gratuit ») |
| T9 | Expérience impossible au regard de l'âge | 2 332 | `exp > age − 14` → `None` |
| T10 | Deux formats de date dans la même colonne | 2 371 en `DD-MM-YYYY` | essayer les deux formats (voir « Dates ») |
| T11 | Promotion jamais eue | 2 330 `last_promotion_date` vides | `None` **conservé** : c'est une information |
| T12 | Valeurs hors schéma (niveau `Boss`, score hors 1-10…) | — | `validate_record` → `SchemaError` |
| T13 | Doublons possibles | 0 dans le fichier | contrôle gardé à l'ingestion (`id`) |

### T1-T2 : extraction robuste

```python
import requests

def download_file(url, dest_path, timeout=60):
    response = requests.get(url, timeout=timeout, stream=True)   # timeout : ne jamais bloquer indéfiniment
    response.raise_for_status()                                  # 404 / 500 -> exception au lieu d'un fichier vide
    with open(dest_path, "wb") as f:
        for chunk in response.iter_content(chunk_size=1024 * 1024):   # par morceaux : pas tout en mémoire
            f.write(chunk)

with open(path, encoding="utf-8") as f:
    data = json.load(f)                          # json.JSONDecodeError si le fichier est corrompu
if not isinstance(data, dict) or "employees" not in data:
    raise ValueError("Format inattendu : clé 'employees' absente")
employees = data["employees"]
```

Pour lister **toutes les clés**, imbriquées comprises (une clé absente d'une partie des lignes deviendra des `None`) :
```python
keys = {}
for e in employees:
    for k, v in e.items():
        if isinstance(v, dict):
            keys.setdefault(k, set()).update(v.keys())
        else:
            keys.setdefault(k, set())
```

### T3 : aplatissement « maison » (`flatten`)

Le sujet impose des règles précises que `pd.json_normalize` ne respecte pas :
1. les clés imbriquées sont concaténées avec `_` (`personal` + `age` → `personal_age`) ;
2. toutes les lignes ont **les mêmes colonnes** : `None` si la clé est absente ;
3. si un nom est à la fois une **valeur simple** dans une ligne et un **parent** dans une autre
   (`"A": 4` et `"A": {"A": 0}`), la valeur simple est renommée `A*`.

```python
def flatten_one(record, parent="", sep="_"):
    """{"A": {"B": 1}} -> {"A_B": 1}  (récursif : gère n'importe quelle profondeur)"""
    flat = {}
    for k, v in record.items():
        name = f"{parent}{sep}{k}" if parent else k
        if isinstance(v, dict):
            flat.update(flatten_one(v, name, sep))
        else:
            flat[name] = v
    return flat

def parent_names(record, parent="", sep="_"):
    """Noms des clés qui contiennent un dictionnaire."""
    names = set()
    for k, v in record.items():
        name = f"{parent}{sep}{k}" if parent else k
        if isinstance(v, dict):
            names |= {name} | parent_names(v, name, sep)
    return names

def flatten(records):
    parents = set().union(*(parent_names(r) for r in records))
    rows = [{(k + "*" if k in parents else k): v for k, v in flatten_one(r).items()} for r in records]
    columns = list(dict.fromkeys(k for row in rows for k in row))   # union des colonnes, ordre conservé
    return [{c: row.get(c) for c in columns} for row in rows]       # row.get -> None si absente

exemple = [{"A": {"A": 0}, "B": 1}, {"B": 2, "C": 3}, {"A": 4}]
assert flatten(exemple) == [
    {"A*": None, "A_A": 0, "B": 1, "C": None},
    {"A*": None, "A_A": None, "B": 2, "C": 3},
    {"A*": 4, "A_A": None, "B": None, "C": None},
]
```

| | `pd.json_normalize` | `flatten` maison |
|---|---|---|
| Séparateur | `.` (modifiable avec `sep="_"`) | `_` |
| Collision `A` / `A.A` | colonnes `A` et `A.A`, sans le suffixe `*` exigé | `A*` et `A_A` |
| Manquants | `NaN` (et entiers convertis en `float` : `0` → `0.0`) | `None`, types d'origine conservés |
| Contrôle des règles | aucun | total, testable avec `assert` |
| Rapidité | très rapide (vectorisé) | plus lent, mais suffisant pour 50 000 lignes |

### T4 : lignes hors périmètre

```python
no_company = df["company_name"].isna()
df[no_company][["personal_email", "personal_age", "job_salary"]].head()  # gmail, âges 0-16, pas de salaire
df = df[~no_company].copy()
```
Les 2 063 lignes sans `company` / `job` / `experience` sont **les mêmes**. Ce ne sont pas des
manquants aléatoires : ce sont des personnes qui ne travaillent pas dans une GAFAM. On ne les
impute pas, on les **sort du périmètre** de l'analyse. La correction les garde en base dans la
table `employees`, sans ligne dans `jobs`.

> **Réflexe d'examen** : quand plusieurs colonnes sont manquantes **sur les mêmes lignes**, chercher
> ce que ces lignes ont en commun avant de décider.

### T5 : manquants déguisés (chaînes vides)

```python
(df == "").sum()[lambda s: s > 0]        # combien de "" par colonne ?
df = df.replace("", None)                # "" -> vraie valeur manquante
df.isna().sum()[lambda s: s > 0]

# Version ligne par ligne (etl.py)
def _empty_to_none(value):
    if isinstance(value, str):
        value = value.strip()            # "   " est aussi une chaîne vide
    return value or None
```
`df.isna()` ne voit **pas** les `""`. Sans cette étape, une colonne paraît complète alors qu'elle ne l'est pas.

### T6 : normaliser une catégorie écrite de plusieurs façons

```python
df["personal_gender"].value_counts(dropna=False)     # M, Male, male, F, Female, female
GENDER_MAP = {"m": "M", "male": "M", "f": "F", "female": "F"}
df["personal_gender"] = df["personal_gender"].str.strip().str.lower().map(GENDER_MAP)
```
- `.str.lower()` **puis** le dictionnaire : on n'a que 4 entrées au lieu de 6+.
- `.map()` renvoie `NaN` pour une valeur absente du dictionnaire : relancer
  `value_counts(dropna=False)` après coup pour vérifier qu'aucune écriture n'a été oubliée.
- Même méthode pour les pays (`"EE. UU."` → `"United States"`), les booléens (`"yes"` / `"Y"` / `True`)…

### T7-T8 : valeurs numériques impossibles

```python
num_cols = df.select_dtypes("number").columns.drop("id")
df[num_cols].describe().T[["min", "max"]]            # repérer min < 0, max absurdes

df["personal_age"] = df["personal_age"].abs()                              # T7 : erreur de signe
df["experience_experience_years"] = df["experience_experience_years"].abs()
df.loc[df["job_salary"] <= 0, "job_salary"] = None                         # T8 : 0 = inconnu
```
- **Pourquoi `abs()` et pas une suppression ?** L'histogramme des valeurs négatives est le **miroir**
  exact des positives : c'est une erreur de signe systématique. La valeur absolue récupère l'information.
- **Pourquoi `None` et pas la médiane pour le salaire ?** Le salaire est la **cible** du modèle :
  imputer une cible fabrique des exemples faux. Les lignes sans salaire sont écartées à l'entraînement
  (45 532 lignes utilisées au lieu de 47 937).

### T9 : cohérence entre deux colonnes

```python
impossible = df["experience_experience_years"] > df["personal_age"] - 14   # pas de travail avant 14 ans
print(impossible.sum(), "expériences impossibles")
df.loc[impossible, "experience_experience_years"] = None
```
On ne sait pas laquelle des deux valeurs est fausse : on invalide celle qui est la **moins fiable**
(l'expérience) plutôt que de supprimer toute la ligne.

### T12 : valider le schéma ligne par ligne

```python
class SchemaError(ValueError):
    pass

POSITION_LEVELS = {"Junior", "Mid", "Senior"}

def validate_record(rec):
    if not isinstance(rec.get("id"), int) or rec["id"] < 0:
        raise SchemaError(f"id invalide : {rec.get('id')!r}")
    if rec["age"] is None or not 0 <= rec["age"] <= 120:
        raise SchemaError(f"id={rec['id']} : âge invalide {rec['age']!r}")
    if rec["company_name"]:                                       # contrôles propres au poste
        if rec["position_level"] not in POSITION_LEVELS:
            raise SchemaError(f"id={rec['id']} : niveau invalide {rec['position_level']!r}")
        if rec["join_date"] and rec["join_date"] > date.today():
            raise SchemaError(f"id={rec['id']} : date d'arrivée dans le futur")
    return rec

# Pipeline : une ligne en erreur est loguée et sautée, les autres continuent
for row in flatten(records):
    try:
        clean_rows.append(validate_record(clean_record(row)))
    except Exception as e:
        log.warning("Ligne ignorée : %s", e)
```
- Une **exception dédiée** (`SchemaError`) permet de la distinguer d'un vrai bug et de la tester avec
  `pytest.raises(SchemaError)`.
- Conversions défensives : `_to_int("")`, `_to_int("abc")` → `None` au lieu de planter.

```python
def _to_int(value):
    if value is None or value == "":
        return None
    try:
        return int(float(value))          # accepte "42", 42.0, "42.0"
    except (TypeError, ValueError):
        return None
```

### T13 : doublons

```python
df["id"].duplicated().sum()                          # même identifiant
df.drop(columns="id").duplicated().sum()             # même contenu sous deux id différents
df = df.drop_duplicates(subset="id")
```
Le deuxième contrôle est souvent oublié : un même employé saisi deux fois reçoit deux `id` différents.
Même à 0, le contrôle reste dans le code : un **prochain fichier** peut en contenir. À l'ingestion,
la correction vérifie aussi qu'un `id` n'existe pas déjà en base, ce qui rend le script relançable.

### pandas « colonne » ou fonctions « ligne » : quand utiliser quoi ?

| | pandas vectorisé (notebook) | Fonctions ligne par ligne (`etl.py`) |
|---|---|---|
| Vitesse | très rapide | plus lent |
| Une valeur invalide | peut faire échouer toute la colonne | n'écarte que **sa** ligne (loguée) |
| Tests unitaires | sur un DataFrame | sur un simple `dict` : très simple |
| Réutilisation | analyse, entraînement | ingestion ligne à ligne via l'ORM |

### Note pandas 3 (version de `exam_bloc2`)

- Les colonnes de texte ont le type **`str`** par défaut (et non plus `object`) : `df.dtypes` affiche
  `str`. `select_dtypes("object")` les inclut encore, mais avec un avertissement (comportement
  déprécié) : écrire `select_dtypes(include=["object", "str"])`.
- **Copy-on-Write** : l'affectation « chaînée » `df["col"][masque] = valeur` ne modifie **plus** `df`.
  Toujours écrire `df.loc[masque, "col"] = valeur` (comme pour T8 et T9).

---

## Les modifications de date

Les dates arrivent presque toujours en **texte** (`"2018-01-31T22:56:00"`). Tant qu'elles ne sont
pas converties, on ne peut ni trier correctement, ni calculer une durée, ni regrouper par mois.

### Convertir

```python
df["date order"] = pd.to_datetime(df["date order"])                       # ISO 8601 : automatique
pd.to_datetime(df["d"], format="%d/%m/%Y %H:%M")                          # format explicite : plus sûr et rapide
pd.to_datetime(df["d"], dayfirst=True)                                    # "03/02/2018" = 3 février
pd.to_datetime(df["d"], errors="coerce")                                  # valeur invalide -> NaT au lieu d'une erreur
pd.to_datetime(df["timestamp"], unit="s")                                 # timestamp Unix (secondes)
pd.read_csv("f.csv", parse_dates=["order_date"])                          # dès la lecture
```
- `NaT` (*Not a Time*) est le « manquant » des dates : compter les `NaT` après un `errors="coerce"`
  révèle les valeurs mal formées.
- **Piège classique** : `"03/02/2018"` est le 3 février en France mais le 2 mars aux États-Unis.
  Toujours préciser `format=` ou `dayfirst=True` quand le format est ambigu.

Codes de format utiles : `%Y` année (2018), `%m` mois, `%d` jour, `%H` heure, `%M` minute, `%S` seconde,
`%b` mois abrégé (Jan), `%A` nom du jour.

### Plusieurs formats dans la même colonne (cas de la correction)

Dans `extract_async.json`, `job_join_date` mélange `2023-07-12` (ISO) et `12-07-2023` (jour-mois-année),
soit 2 371 dates au second format.

```python
# 1. Détecter : compter les valeurs qui suivent chaque motif
df["job_join_date"].str.match(r"\d{4}-\d{2}-\d{2}").sum()     # YYYY-MM-DD
df["job_join_date"].str.match(r"\d{2}-\d{2}-\d{4}").sum()     # DD-MM-YYYY

# 2. Convertir (pandas) : chaque format avec errors="coerce", puis on combine
for col in ["job_join_date", "job_last_promotion_date"]:
    iso = pd.to_datetime(df[col], format="%Y-%m-%d", errors="coerce")   # NaT pour les DD-MM-YYYY
    fr = pd.to_datetime(df[col], format="%d-%m-%Y", errors="coerce")    # NaT pour les YYYY-MM-DD
    df[col] = iso.fillna(fr)                                             # on bouche les trous de l'un par l'autre

# 3. Vérifier : il ne doit rester de NaT que là où la valeur d'origine était vide
```

Version ligne par ligne (`etl.py`), avec le module standard `datetime` :
```python
from datetime import datetime

DATE_FORMATS = ("%Y-%m-%d", "%d-%m-%Y")

def _to_date(value):
    if not value:
        return None
    for fmt in DATE_FORMATS:              # on essaie chaque format connu
        try:
            return datetime.strptime(str(value), fmt).date()
        except ValueError:
            pass
    return None                           # aucun format ne marche -> valeur invalide
```

> **Pourquoi pas `pd.to_datetime(df[col])` sans format ?** pandas devine le format à partir de la
> première valeur puis l'applique à toute la colonne. Sur ce fichier, il lève
> `ValueError: time data "07-08-2018" doesn't match format "%Y-%m-%d"`. Avec `errors="coerce"`,
> ces dates deviendraient silencieusement `NaT`. Et pour des formats proches (`01/02` contre `02/01`),
> le jour et le mois peuvent être inversés **sans aucun message**.
> `format="mixed"` existe mais devine valeur par valeur : à éviter quand on connaît les formats.

> `strptime` = *string parse time* (texte → date) ; `strftime` = *string format time* (date → texte).

### Contrôles de cohérence entre dates

```python
# Une promotion ne peut pas précéder l'arrivée dans l'entreprise
(df["job_last_promotion_date"] < df["job_join_date"]).sum()
# Pas de date dans le futur
(df["job_join_date"] > pd.Timestamp.today()).sum()
# Plage plausible
df[["job_join_date", "job_last_promotion_date"]].describe()   # min / max
```
Une date **manquante** n'est pas forcément une erreur : `last_promotion_date` vide signifie
« jamais promu ». On garde `None` (`NaT`) plutôt que d'inventer une date. On peut en tirer une
feature : `jamais_promu = df["job_last_promotion_date"].isna()`, ou une ancienneté :
`(pd.Timestamp.today() - df["job_join_date"]).dt.days`.

### Extraire des composantes (accesseur `.dt`)

```python
d = df["date order"]
d.dt.year, d.dt.month, d.dt.day, d.dt.hour
d.dt.weekday          # 0 = lundi ... 6 = dimanche
d.dt.day_name()       # "Monday"...
d.dt.quarter          # trimestre
d.dt.date             # partie date seule
d.dt.to_period("M")   # période mensuelle (2018-01), pratique pour grouper
d.dt.strftime("%d/%m/%Y")   # retour en texte formaté (affichage, export)
```
Ces composantes deviennent des **features** pour le ML (`order_hour`, `order_weekday`, `order_month`
dans `train.py`). Le jour de la semaine ou le mois peuvent porter un effet saisonnier.

### Calculer des durées et décaler des dates

```python
delai = df["date shipping"] - df["date order"]       # Timedelta
df["shipping_days"] = delai.dt.days                   # nombre de jours entiers
delai.dt.total_seconds() / 3600                       # durée en heures

df["date order"] + pd.Timedelta(days=7)               # + 7 jours exactement
df["date order"] + pd.DateOffset(months=1)            # + 1 mois calendaire : 31/01 -> 28/02
df["date order"].dt.normalize()                       # remet l'heure à 00:00
df["date order"].dt.floor("h")                        # arrondi à l'heure inférieure
```
Contrôle de cohérence indispensable : une durée **négative** (expédition avant commande) est une erreur
de données → règle dans `validate()`.

### Filtrer, trier, regrouper dans le temps

```python
df[df["date order"] >= "2017-07-01"]                              # comparaison directe avec une chaîne
df[df["date order"].between("2017-01-01", "2017-12-31")]
df.sort_values("date order")

ts = df.set_index("date order").sort_index()
ts.loc["2017-03"]                                                  # tout mars 2017 (index trié)
ts["sales"].resample("MS").sum()      # par mois (MS = début de mois) ; "D", "W", "QS", "YS"
ts["sales"].resample("W").sum().rolling(4).mean()                 # moyenne mobile sur 4 semaines
df.groupby(df["date order"].dt.to_period("M"))["sales"].sum()     # équivalent sans index
```

### Fuseaux horaires

```python
s = pd.to_datetime(df["date order"])          # "naïve" : aucun fuseau
s.dt.tz_localize("UTC")                       # déclarer le fuseau d'origine
s.dt.tz_localize("UTC").dt.tz_convert("Europe/Paris")   # convertir pour l'affichage
```
Bonne pratique : **stocker en UTC** et convertir seulement à l'affichage. On ne peut pas comparer
une date avec fuseau et une date sans fuseau (pandas lève une erreur).

### Dates et base de données

- Avec l'ORM, une colonne `DateTime` reçoit des objets `datetime` Python : convertir **avant** l'insertion.
- **SQLite n'a pas de vrai type date** : il stocke du texte ISO (`"2018-01-31 22:56:00.000000"`). Il faut
  donc reconvertir à la lecture : `pd.read_sql(..., parse_dates=["order_date"])` (fait dans `train.py`).
- MySQL et PostgreSQL ont de vrais types `DATETIME` / `TIMESTAMP`. Fonctions SQL utiles :
  `YEAR(d)`, `DATEDIFF(d1, d2)` (MySQL) ; `EXTRACT(YEAR FROM d)`, `d1 - d2` (PostgreSQL) ;
  `strftime('%Y', d)`, `julianday(d1) - julianday(d2)` (SQLite).

### Pièges à citer à l'oral

| Piège | Conséquence | Parade |
|---|---|---|
| Date restée en texte | tri alphabétique faux (`"10/01"` avant `"9/01"`), pas de calcul | `pd.to_datetime` |
| Format jour/mois ambigu | dates inversées sans erreur visible | `format=` ou `dayfirst=True` |
| Deux formats dans une colonne | une partie en `NaT` ou inversée | un `to_datetime` par format + `fillna` |
| Valeurs invalides | erreur au chargement | `errors="coerce"` puis compter les `NaT` |
| Période incomplète (janvier 2018) | fausse « chute » sur les graphiques | la repérer avec `min()`/`max()`, l'exclure ou l'annoter |
| Fuseaux mélangés | décalages d'heures, comparaisons impossibles | tout ramener en UTC |
| Date future utilisée comme feature | **fuite de données** (ex. date d'expédition) | n'utiliser que ce qui est connu au moment de la prédiction |
| Découpage train/test aléatoire sur des données temporelles | performance surestimée | découpage chronologique (`train.py`) |
