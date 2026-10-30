# Aide-mémoire — Tester les transformations (pytest)

> Suite de `AIDE_MEMOIRE_EXPLORATION.md` : un test pour chaque transformation **T1 → T13** de
> `bloc2_correction/etl.py` (sujet Stonewindow).
> Tous les tests de cette fiche ont été **exécutés** dans l'environnement `exam_bloc2`
> (Python 3.12, pandas 3.1, pytest) : **62 réussis, 1 échec attendu (`xfail`)**.
> Pour les bases (`fixture`, `monkeypatch`, `Mock`), voir `02_tests_pytest_mock.ipynb`.

---

## 0. Mise en place

Copier les blocs de code de cette fiche, dans l'ordre, dans un fichier
`bloc2_correction/test_transformations.py` (à côté de `etl.py`), puis, dans la WSL :

```bash
cd /mnt/c/Users/Alexandre/Desktop/fiches_revision/bloc2_correction
pyenv activate exam_bloc2           # ou une fois pour toutes : pyenv local exam_bloc2
python -m pytest test_transformations.py -v
```

Options utiles : `-k genre` (seulement les tests dont le nom contient *genre*), `-x` (s'arrêter au
premier échec), `--lf` (relancer les derniers échecs), `-rx` (afficher le détail des `xfail`).

### Que tester, et comment ?

| Principe | Application |
|---|---|
| Un test = **une** règle | `test_salaire`, `test_normalisation_du_genre`… : le nom dit ce qui casse |
| Entrée brute → sortie attendue | on part d'un dict comme dans le JSON, on vérifie le dict nettoyé |
| 3 familles de cas | **normal** (valeur correcte gardée), **à corriger** (`-5` → `5`), **invalide** (`Boss` → erreur) |
| Tester les **limites** | `age - 14` pile (accepté) et `+ 1` (refusé) |
| Pas de réseau, pas de vraie base | `patch` pour `requests`, `tmp_path` pour les fichiers, SQLite en mémoire |
| Données minuscules et maîtrisées | une ligne fabriquée, jamais le fichier de 64 Mo |

---

## 1. Imports et données de test

Une **ligne brute de référence** (`RAW`) parfaitement valide, et une fonction qui en fabrique des
variantes en ne changeant qu'**un seul champ**. Chaque test montre ainsi exactement ce qu'il change.

```python
import json
import logging
from datetime import date
from unittest.mock import Mock, patch

import pandas as pd
import pytest
import requests

import etl
from etl import (
    SchemaError, _empty_to_none, _to_date, _to_int, clean_record, flatten,
    load_employees, transform, unique_keys, validate_record,
)

RAW = {
    "id": 1,
    "personal": {"first_name": "Ana", "last_name": "Lopez", "email": "ana@apple.es",
                 "country": "Spain", "age": 30, "gender": "F", "marital_status": "Single"},
    "company": {"name": "Apple", "num_employees": 154000, "benefits": "x",
                "main_area_of_expertise": "y", "headquarters": "z"},
    "job": {"salary": 68000, "department": "HR", "join_date": "2020-01-01",
            "position_level": "Mid", "performance_score": 4, "last_promotion_date": "2021-06-01"},
    "experience": {"experience_years": 5, "has_certifications": True, "education_level": "PhD",
                   "work_hours_per_week": 40, "projects_completed": 3},
}


def raw_with(**changes):
    """Copie de RAW avec des champs imbriqués modifiés : raw_with(personal_age=-30)."""
    raw = json.loads(json.dumps(RAW))          # copie PROFONDE : RAW n'est jamais modifié
    for key, value in changes.items():
        bloc, champ = key.split("_", 1)        # "personal_age" -> ("personal", "age")
        raw[bloc][champ] = value
    return raw


def clean(raw):
    """Raccourci : aplatit une seule ligne puis la nettoie."""
    return clean_record(flatten([raw])[0])


@pytest.fixture
def rec():
    return clean(RAW)
```

> **Piège** : `dict(RAW)` ou `RAW.copy()` ne copient que le premier niveau. Modifier
> `copie["personal"]["age"]` modifierait aussi `RAW`, et donc **les autres tests**. D'où la
> copie profonde (`json.loads(json.dumps(...))` ou `copy.deepcopy`).

---

## 2. T1-T2 : extraction (fichier, réseau)

### Téléchargement : on remplace `requests.get` par un `Mock`

```python
def test_download_ecrit_le_fichier(tmp_path):
    fausse_reponse = Mock()
    fausse_reponse.iter_content.return_value = [b'{"employees": ', b"[]}"]   # 2 "morceaux"
    with patch("etl.requests.get", return_value=fausse_reponse) as mock_get:
        chemin = etl.download_file("https://exemple/f.json", tmp_path / "f.json")
    assert (tmp_path / "f.json").read_bytes() == b'{"employees": []}'
    assert chemin == tmp_path / "f.json"
    mock_get.assert_called_once_with("https://exemple/f.json", timeout=60, stream=True)


def test_download_erreur_http(tmp_path):
    fausse_reponse = Mock()
    fausse_reponse.raise_for_status.side_effect = requests.HTTPError("404 Not Found")
    with patch("etl.requests.get", return_value=fausse_reponse):
        with pytest.raises(requests.HTTPError):
            etl.download_file("https://exemple/absent.json", tmp_path / "f.json")
    assert not (tmp_path / "f.json").exists()       # aucun fichier vide laissé derrière
```
- Aucun accès Internet : le test est **rapide**, marche **hors ligne** et en CI.
- `assert_called_once_with(..., timeout=60, ...)` vérifie qu'on n'a pas oublié le `timeout`.
- `etl.py` fait `import requests`, donc `patch("etl.requests.get")` et `patch("requests.get")`
  fonctionnent tous les deux. Avec `from requests import get`, seul `patch("etl.get")` marcherait
  (règle « patcher là où c'est utilisé »).

### Lecture du JSON : `tmp_path` + cas d'erreur

```python
def test_load_employees(tmp_path):
    chemin = tmp_path / "ok.json"
    chemin.write_text(json.dumps({"employees": [RAW]}), encoding="utf-8")
    assert load_employees(chemin) == [RAW]


@pytest.mark.parametrize("contenu", ['{"autre": []}', "[1, 2]"])
def test_load_employees_mauvais_format(tmp_path, contenu):
    chemin = tmp_path / "ko.json"
    chemin.write_text(contenu, encoding="utf-8")
    with pytest.raises(ValueError, match="employees"):
        load_employees(chemin)


def test_load_employees_fichier_corrompu(tmp_path):
    chemin = tmp_path / "corrompu.json"
    chemin.write_text('{"employees": [', encoding="utf-8")       # JSON tronqué
    with pytest.raises(json.JSONDecodeError):
        load_employees(chemin)
```

---

## 3. T3 : aplatissement

```python
def test_flatten_exemple_du_sujet():
    data = [{"A": {"A": 0}, "B": 1}, {"B": 2, "C": 3}, {"A": 4}]
    assert flatten(data) == [
        {"A*": None, "A_A": 0, "B": 1, "C": None},
        {"A*": None, "A_A": None, "B": 2, "C": 3},
        {"A*": 4, "A_A": None, "B": None, "C": None},
    ]


def test_flatten_toutes_les_lignes_ont_les_memes_colonnes():
    lignes = flatten([RAW, {"id": 2, "personal": {"age": 20}}])
    assert lignes[0].keys() == lignes[1].keys()
    assert lignes[1]["job_salary"] is None


def test_flatten_plusieurs_niveaux():
    assert flatten([{"a": {"b": {"c": 1}}}]) == [{"a_b_c": 1}]


def test_flatten_liste_vide():
    assert flatten([]) == []


def test_flatten_ne_modifie_pas_l_entree():
    copie = json.loads(json.dumps(RAW))
    flatten([RAW])
    assert RAW == copie


def test_unique_keys():
    keys = unique_keys([RAW, {"id": 2, "personal": {"age": 20}}])
    assert "personal_age" in keys and "job_salary" in keys
    assert len(keys) == len(set(keys))              # pas de doublon dans la liste
```
L'**exemple du sujet** est le premier test à écrire : c'est la spécification officielle.
Les autres couvrent les cas que l'exemple ne montre pas : profondeur, liste vide, effet de bord.

---

## 4. T4-T9 : nettoyage d'une ligne

### T4 : hors périmètre

```python
def test_transform_retire_les_personnes_sans_entreprise():
    sans_job = {"id": 2, "personal": {"age": 20, "gender": "M"}}
    df = transform([RAW, sans_job])
    assert list(df["id"]) == [1]
```

### T5 : chaînes vides

```python
@pytest.mark.parametrize("valeur, attendu", [
    ("", None), ("   ", None), (None, None), (" Married ", "Married"), ("Single", "Single"),
])
def test_empty_to_none(valeur, attendu):
    assert _empty_to_none(valeur) == attendu


def test_clean_record_chaine_vide():
    assert clean(raw_with(personal_marital_status=""))["marital_status"] is None
```

### T6 : une catégorie écrite de plusieurs façons

```python
@pytest.mark.parametrize("brut, attendu", [
    ("M", "M"), ("Male", "M"), ("male", "M"), (" MALE ", "M"),
    ("F", "F"), ("Female", "F"), ("female", "F"),
    ("X", None), ("", None), (None, None),
])
def test_normalisation_du_genre(brut, attendu):
    assert clean(raw_with(personal_gender=brut))["gender"] == attendu
```
`parametrize` est idéal ici : **une ligne par écriture rencontrée** dans les données (les 6 de
`value_counts()`), plus les cas imprévus (`"X"`, `" MALE "`, vide). Le rapport affiche un test par ligne.

### T7 : erreur de signe

```python
@pytest.mark.parametrize("champ, cle", [("personal_age", "age"),
                                        ("experience_experience_years", "experience_years")])
def test_valeurs_negatives_passees_en_absolu(champ, cle):
    assert clean(raw_with(**{champ: -5}))[cle] == 5
```

### T8 : salaire nul ou absent

```python
@pytest.mark.parametrize("salaire, attendu", [(0, None), (-100, None), (68000, 68000), ("", None)])
def test_salaire(salaire, attendu):
    assert clean(raw_with(job_salary=salaire))["salary"] == attendu
```
Toujours inclure le **cas normal** (`68000` → `68000`) : un nettoyage trop zélé qui effacerait tous
les salaires ferait passer les autres cas.

### T9 : cohérence entre deux colonnes, tester la limite

```python
@pytest.mark.parametrize("age, exp, attendu", [
    (30, 16, 16),       # limite : 30 - 14 = 16 -> accepté
    (30, 17, None),     # une année de trop -> impossible
    (30, -20, None),    # abs(-20) = 20 > 16 -> impossible (T7 puis T9)
])
def test_experience_coherente_avec_l_age(age, exp, attendu):
    raw = raw_with(personal_age=age, experience_experience_years=exp)
    assert clean(raw)["experience_years"] == attendu
```
Les bugs se cachent aux **frontières** : `>` au lieu de `>=` ne se voit qu'avec la valeur pile à la limite.
Le 3ᵉ cas vérifie aussi l'**ordre** des transformations (valeur absolue d'abord, cohérence ensuite).

---

## 5. T10-T11 : dates

```python
@pytest.mark.parametrize("texte, attendu", [
    ("2023-07-12", date(2023, 7, 12)),
    ("12-07-2023", date(2023, 7, 12)),
    ("12/07/2023", None),           # format inconnu
    ("2023-02-30", None),           # date impossible
    ("", None), (None, None),
])
def test_to_date(texte, attendu):
    assert _to_date(texte) == attendu


def test_deux_formats_donnent_la_meme_date():
    iso = clean(raw_with(job_join_date="2022-01-16"))["join_date"]
    fr = clean(raw_with(job_join_date="16-01-2022"))["join_date"]
    assert iso == fr == date(2022, 1, 16)


def test_jamais_promu_reste_none():
    assert clean(raw_with(job_last_promotion_date=None))["last_promotion_date"] is None
```
- On compare avec un objet `date(...)`, **pas** avec une chaîne : on vérifie aussi le **type** produit.
- Choisir un jour **> 12** (`16-01`) : avec `01-02`, une inversion jour/mois passerait inaperçue.
- `"2023-02-30"` : le format est bon mais la date n'existe pas → `strptime` lève une erreur, convertie en `None`.

---

## 6. T12 : validation du schéma et conversions

```python
@pytest.mark.parametrize("valeur, attendu", [
    ("42", 42), (42.0, 42), ("42.0", 42), ("", None), ("abc", None), (None, None),
])
def test_to_int(valeur, attendu):
    assert _to_int(valeur) == attendu


def test_validate_accepte_une_ligne_correcte(rec):
    assert validate_record(rec) is rec


@pytest.mark.parametrize("changes, message", [
    ({"job_position_level": "Boss"}, "niveau"),
    ({"job_performance_score": 11}, "score"),
    ({"personal_age": 150}, "âge"),
    ({"job_join_date": "2999-01-01"}, "futur"),
], ids=["niveau", "score", "age", "date_future"])
def test_validate_rejette(changes, message):
    with pytest.raises(SchemaError, match=message):
        validate_record(clean(raw_with(**changes)))


def test_validate_rejette_un_id_non_entier():
    with pytest.raises(SchemaError, match="id"):
        validate_record(clean({**RAW, "id": "abc"}))
```
- `match=` vérifie **quelle** règle a rejeté la ligne. Sans lui, le test passerait même si la ligne
  était rejetée pour une autre raison.
- `ids=[...]` donne des noms lisibles dans le rapport : `test_validate_rejette[date_future]`.

### Vérifier qu'une ligne invalide est logguée et sautée (`caplog`)

```python
def test_transform_logue_et_saute_les_lignes_invalides(caplog):
    with caplog.at_level(logging.WARNING):
        df = transform([RAW, raw_with(job_position_level="Boss")])
    assert len(df) == 1                       # la ligne valide est gardée
    assert "Ligne ignorée" in caplog.text     # l'autre est tracée, pas perdue en silence
```

### Un cas limite trouvé par les tests (`xfail`)

```python
@pytest.mark.xfail(raises=KeyError, reason="DataFrame vide sans colonne 'id' : drop_duplicates plante")
def test_transform_que_des_lignes_invalides():
    assert transform([{"id": "abc"}]).empty
```
Si **toutes** les lignes sont invalides, `pd.DataFrame([])` n'a aucune colonne et
`drop_duplicates(subset="id")` lève `KeyError`. `xfail` documente ce bug connu sans casser la suite.
Le jour où il est corrigé, pytest affiche `XPASS` : il faut alors retirer le marqueur.
Correction possible : `if not clean_rows: return pd.DataFrame(columns=[...])`.

---

## 7. T13 : doublons

```python
def test_transform_supprime_les_doublons_d_id():
    assert len(transform([RAW, RAW])) == 1
```
Côté base, `bloc2_correction/test_etl.py` teste l'ingestion dans une **SQLite en mémoire**
(`create_engine("sqlite://")`) : une ligne en double dans le fichier est comptée dans
`stats["duplicates"]`, et **relancer** l'ingestion n'ajoute rien (idempotence).
Extrait pour mémoire (déjà présent dans `test_etl.py`, **ne pas recopier**) :

```python
# --- extrait de test_etl.py ---
@pytest.fixture
def engine():
    return create_engine("sqlite://")          # base jetable, recréée pour chaque test

def test_ingestion_sans_doublons(engine):
    stats = ingest([RAW, RAW, sans_job], engine)
    assert stats == {"inserted": 2, "duplicates": 1, "invalid": 0}
    ingest([RAW, sans_job], engine)            # 2e lancement : rien de neuf
    assert count(engine, Employee) == 2
```

---

## 8. Tester la version pandas (notebook)

Pour comparer des `Series` ou des `DataFrame`, on n'utilise pas `==` (qui renvoie une Series de booléens,
et `NaN != NaN`) mais les fonctions de `pd.testing` :

```python
def normaliser_genre(serie: pd.Series) -> pd.Series:
    mapping = {"m": "M", "male": "M", "f": "F", "female": "F"}
    return serie.str.strip().str.lower().map(mapping)


def test_normaliser_genre_pandas():
    entree = pd.Series(["Male", "female", "M", "X"])
    attendu = pd.Series(["M", "F", "M", None])
    pd.testing.assert_series_equal(normaliser_genre(entree), attendu, check_dtype=False)


def test_deux_formats_de_date_pandas():
    df = pd.DataFrame({"d": ["2023-07-12", "12-07-2023", None]})
    iso = pd.to_datetime(df["d"], format="%Y-%m-%d", errors="coerce")
    fr = pd.to_datetime(df["d"], format="%d-%m-%Y", errors="coerce")
    resultat = iso.fillna(fr)
    attendu = pd.Series(pd.to_datetime(["2023-07-12", "2023-07-12", None]), name="d")
    pd.testing.assert_series_equal(resultat, attendu)
```
- `assert_series_equal` / `assert_frame_equal` considèrent deux `NaN` comme égaux et affichent un diff précis.
- `check_dtype=False` : ignore la différence `str` / `object` (fréquente avec pandas 3).
- Pour tester une transformation de notebook, il faut d'abord la **sortir dans une fonction**.
  C'est l'intérêt de passer du notebook à `etl.py`.

---

## 9. Antisèche

| Besoin | Outil |
|---|---|
| Plusieurs cas pour une même règle | `@pytest.mark.parametrize("entree, attendu", [...], ids=[...])` |
| Vérifier une exception **et** son motif | `with pytest.raises(SchemaError, match="niveau"):` |
| Fichier temporaire | fixture `tmp_path` |
| Pas de réseau | `patch("etl.requests.get", return_value=Mock(...))` |
| Simuler une erreur | `mock.side_effect = requests.HTTPError("404")` |
| Vérifier les arguments d'un appel | `mock.assert_called_once_with(url, timeout=60, stream=True)` |
| Vérifier un log | fixture `caplog` + `caplog.at_level(logging.WARNING)` |
| Comparer des Series / DataFrame | `pd.testing.assert_series_equal` / `assert_frame_equal` |
| Base de données jetable | `create_engine("sqlite://")` |
| Bug connu, pas encore corrigé | `@pytest.mark.xfail(raises=..., reason=...)` |
| Variable d'environnement | `monkeypatch.setenv("MYSQL_HOST", "localhost")` |

**Questions classiques à l'oral**
- *Pourquoi tester ligne par ligne plutôt que sur tout le fichier ?* Un test sur 50 000 lignes est lent,
  et en cas d'échec on ne sait pas quelle règle a cassé. Une ligne fabriquée isole **une** règle.
- *Pourquoi ne pas télécharger le vrai fichier dans les tests ?* Lenteur, dépendance au réseau et à S3,
  données qui peuvent changer : le test ne serait plus reproductible.
- *Que vérifie un bon test de nettoyage ?* Le cas corrigé, le cas normal **inchangé**, le cas
  invalide **rejeté**, et la valeur **limite**.
- *Qu'est-ce qu'un test de régression ?* Un test écrit pour un bug trouvé (comme le `xfail`) : il garantit
  que ce bug ne reviendra pas une fois corrigé.
