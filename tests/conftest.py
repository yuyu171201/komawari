import copy

import pytest

from komawari.config import parse_config

BASE = {
    "term": {"start": "2026-10-05", "end": "2027-01-29"},
    "periods": {
        1: {"start": "08:45", "end": "10:15"},
        2: {"start": "10:30", "end": "12:00"},
        3: {"start": "13:00", "end": "14:30"},
        4: {"start": "14:45", "end": "16:15"},
        5: {"start": "16:30", "end": "18:00"},
    },
    "classes": [
        {"name": "Java演習", "weekday": 0, "period": 2, "room": "情報1号館"},
        {"name": "機械学習", "weekday": 2, "period": 3, "room": "A101"},
        {"name": "ゼミ", "weekday": 4, "start": "18:10", "end": "19:40"},
    ],
}


@pytest.fixture
def make_cfg():
    """BASE に例外（と任意の上書き）を足した Config を作る。"""

    def _make(exceptions=(), **overrides):
        raw = copy.deepcopy(BASE)
        raw["exceptions"] = list(exceptions)
        raw.update(overrides)
        return parse_config(raw)

    return _make
