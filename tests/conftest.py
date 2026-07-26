from __future__ import annotations

import random
from pathlib import Path

import chess
import pytest

DATA = Path(__file__).parent / "data"


def playout(seed: int, plies: int) -> chess.Board:
    """A position reached by random legal play - cheap, diverse, always legal."""
    rng = random.Random(seed)
    board = chess.Board()
    for _ in range(plies):
        moves = list(board.legal_moves)
        if not moves:
            break
        board.push(rng.choice(moves))
    board.halfmove_clock = 0
    board.fullmove_number = 1
    return board


@pytest.fixture
def reference_image() -> Path:
    """A real screenshot: a different piece set, a highlighted square, inline coordinates."""
    return DATA / "reference_board.png"
