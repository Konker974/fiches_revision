import pytest

from boutique import prix_ttc


@pytest.mark.parametrize(
    "prix_ht, taux, attendu",
    [
        (100, 0.20, 120.0),
        (100, 0.055, 105.5),
        (0, 0.20, 0.0),
        (19.99, 0.20, 23.99),
    ],
    ids=["normal", "reduit", "gratuit", "arrondi"],
)
def test_prix_ttc(prix_ht, taux, attendu):
    assert prix_ttc(prix_ht, taux) == attendu


@pytest.mark.parametrize("prix_invalide", [-1, -0.01, -1000])
def test_prix_invalides(prix_invalide):
    with pytest.raises(ValueError):
        prix_ttc(prix_invalide)
