"""Deterministic, seeded resampling primitives.

Uses numpy's modern ``Generator``/``default_rng`` API (PCG64), not the
legacy global ``numpy.random`` state or ``RandomState`` -- the legacy global
state is process-wide and can be mutated by unrelated code running in the
same process (e.g. another notebook cell, another import), which would
silently break the "repeated tests must produce identical event decisions"/
"randomized analysis uses explicit seeds" reproducibility requirement. A
``Generator`` constructed directly from a seed here is isolated from any
other code's use of numpy's RNG.
"""

from __future__ import annotations

from typing import Iterator

import numpy as np


def seeded_bootstrap_indices(n: int, n_resamples: int, seed: int) -> Iterator[np.ndarray]:
    """Yields 'n_resamples' arrays, each of length 'n', of indices into a
    length-n dataset, drawn WITH replacement (the standard bootstrap),
    using a Generator seeded exactly once from 'seed' -- so the sequence
    of resamples is fully determined by (n, n_resamples, seed) and nothing
    else, byte-for-byte reproducible across runs/machines (numpy's PCG64
    stream is itself specified to be stable across numpy versions for a
    given seed).

    Raises ValueError for n <= 0 or n_resamples <= 0 -- there is no
    meaningful empty resample to silently return.
    """

    if n <= 0:
        raise ValueError(f"seeded_bootstrap_indices: n must be > 0, got {n}")
    if n_resamples <= 0:
        raise ValueError(f"seeded_bootstrap_indices: n_resamples must be > 0, got {n_resamples}")

    rng = np.random.default_rng(seed)
    for _ in range(n_resamples):
        yield rng.integers(0, n, size=n)
