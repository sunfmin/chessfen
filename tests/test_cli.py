from __future__ import annotations

import json

from PIL import Image

from chessfen.cli import main

START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"


def test_recognize_prints_just_the_fen(reference_image, capsys):
    assert main(["recognize", str(reference_image)]) == 0
    assert capsys.readouterr().out.strip() == "r3k3/2N5/8/8/8/8/8/8 w q - 0 1"


def test_turn_flag_reaches_the_fen(reference_image, capsys):
    assert main(["recognize", str(reference_image), "--turn", "b"]) == 0
    assert capsys.readouterr().out.split()[1] == "b"


def test_json_report_lists_the_occupied_squares(reference_image, capsys):
    assert main(["recognize", str(reference_image), "--json"]) == 0
    report = json.loads(capsys.readouterr().out)
    assert {entry["square"]: entry["piece"] for entry in report["squares"]} == {
        "a8": "r",
        "c7": "N",
        "e8": "k",
    }
    assert all(entry["confident"] for entry in report["squares"])


def test_render_then_recognize_round_trips_through_the_cli(tmp_path, capsys):
    out = tmp_path / "board.png"
    assert main(["render", START_FEN, "-o", str(out), "--size", "400"]) == 0
    capsys.readouterr()
    assert main(["recognize", str(out)]) == 0
    assert capsys.readouterr().out.strip() == START_FEN


def test_a_picture_without_a_board_exits_nonzero_with_a_message(tmp_path, capsys):
    blank = tmp_path / "blank.png"
    Image.new("RGB", (400, 400), (180, 170, 160)).save(blank)
    assert main(["recognize", str(blank)]) == 1
    assert "chessfen:" in capsys.readouterr().err
