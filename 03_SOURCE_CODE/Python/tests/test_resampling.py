from __future__ import annotations

import numpy as np
import pytest

from analysis.resampling import seeded_bootstrap_indices


def test_rejects_non_positive_n():
    with pytest.raises(ValueError):
        list(seeded_bootstrap_indices(0, 10, seed=1))


def test_rejects_non_positive_n_resamples():
    with pytest.raises(ValueError):
        list(seeded_bootstrap_indices(10, 0, seed=1))


def test_yields_correct_shape_and_count():
    resamples = list(seeded_bootstrap_indices(5, 3, seed=1))
    assert len(resamples) == 3
    for r in resamples:
        assert len(r) == 5
        assert (r >= 0).all() and (r < 5).all()


def test_deterministic_given_same_seed():
    a = list(seeded_bootstrap_indices(10, 20, seed=123))
    b = list(seeded_bootstrap_indices(10, 20, seed=123))
    for ra, rb in zip(a, b):
        assert np.array_equal(ra, rb)


def test_different_seeds_produce_different_sequences():
    a = list(seeded_bootstrap_indices(10, 20, seed=1))
    b = list(seeded_bootstrap_indices(10, 20, seed=2))
    assert not all(np.array_equal(ra, rb) for ra, rb in zip(a, b))


def test_isolated_from_global_numpy_random_state():
    """Mutating numpy's GLOBAL random state must not affect this
    generator's output -- it is seeded independently (default_rng), not
    drawn from the shared/legacy global state."""

    np.random.seed(999)  # perturb the global legacy state
    first = list(seeded_bootstrap_indices(10, 5, seed=42))
    np.random.seed(1)  # perturb it again, differently
    second = list(seeded_bootstrap_indices(10, 5, seed=42))
    for a, b in zip(first, second):
        assert np.array_equal(a, b)
