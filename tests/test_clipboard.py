"""The clipboard adapter, with the platform clipboard itself stubbed out.

A real clipboard cannot be part of a test run, so what is pinned here is our handling of
the three things ``ImageGrab.grabclipboard`` can hand back: an image, a list of file
paths, or nothing.
"""

from __future__ import annotations

import pytest
from PIL import Image

from chessfen import (
    ClipboardImageError,
    ClipboardWriteError,
    clipboard_image,
    copy_text,
)
from chessfen.cli import main

EXPECTED_FEN = "r3k3/2N5/8/8/8/8/8/8 w q - 0 1"


@pytest.fixture
def clipboard(monkeypatch):
    """Set what the platform clipboard returns; a callable raises instead."""

    def put(value):
        def grab():
            return value() if callable(value) else value

        monkeypatch.setattr("chessfen.clipboard.ImageGrab.grabclipboard", grab)

    return put


def test_a_copied_screenshot_is_recognised(clipboard, reference_image):
    with Image.open(reference_image) as handle:
        clipboard(handle.convert("RGB"))
    assert clipboard_image().shape == (786, 792, 3)


def test_copied_image_with_transparency_is_flattened(clipboard):
    clipboard(Image.new("RGBA", (10, 10), (0, 0, 0, 0)))
    assert clipboard_image().tolist() == [[[255, 255, 255]] * 10] * 10


def test_files_copied_from_a_file_manager_are_loaded(clipboard, reference_image):
    clipboard([str(reference_image)])
    assert clipboard_image().shape == (786, 792, 3)


def test_non_image_files_on_the_clipboard_are_skipped(
    clipboard, reference_image, tmp_path
):
    junk = tmp_path / "notes.txt"
    junk.write_text("not an image")
    clipboard([str(junk), str(reference_image)])
    assert clipboard_image().shape == (786, 792, 3)


def test_an_empty_clipboard_says_so(clipboard):
    clipboard(None)
    with pytest.raises(ClipboardImageError, match="no image"):
        clipboard_image()


def test_a_clipboard_of_only_junk_says_so(clipboard, tmp_path):
    junk = tmp_path / "notes.txt"
    junk.write_text("not an image")
    clipboard([str(junk)])
    with pytest.raises(ClipboardImageError, match="no readable image"):
        clipboard_image()


def test_a_system_without_a_clipboard_tool_says_so(clipboard):
    def explode():
        raise OSError("xclip not found")

    clipboard(explode)
    with pytest.raises(ClipboardImageError, match="cannot read the clipboard"):
        clipboard_image()


def test_copy_text_pipes_into_the_platform_tool(monkeypatch):
    calls = []

    def fake_run(command, *, input, check):
        calls.append((command, input, check))

    monkeypatch.setattr("chessfen.clipboard.sys.platform", "darwin")
    monkeypatch.setattr("chessfen.clipboard.subprocess.run", fake_run)
    copy_text("8/8/8/8/8/8/8/8 w - - 0 1")
    assert calls == [(("pbcopy",), b"8/8/8/8/8/8/8/8 w - - 0 1", True)]


def test_copy_text_tries_the_next_tool_when_one_is_missing(monkeypatch):
    used = []

    def fake_run(command, *, input, check):
        if command[0] == "wl-copy":
            raise FileNotFoundError(command[0])
        used.append(command[0])

    monkeypatch.setattr("chessfen.clipboard.sys.platform", "linux")
    monkeypatch.setattr("chessfen.clipboard.subprocess.run", fake_run)
    copy_text("fen")
    assert used == ["xclip"]


def test_copy_text_names_what_to_install_when_nothing_is_there(monkeypatch):
    def fake_run(command, *, input, check):
        raise FileNotFoundError(command[0])

    monkeypatch.setattr("chessfen.clipboard.sys.platform", "linux")
    monkeypatch.setattr("chessfen.clipboard.subprocess.run", fake_run)
    with pytest.raises(ClipboardWriteError, match="wl-copy or xclip or xsel"):
        copy_text("fen")


def test_copy_text_on_an_unknown_platform_says_so(monkeypatch):
    monkeypatch.setattr("chessfen.clipboard.sys.platform", "plan9")
    with pytest.raises(ClipboardWriteError, match="a clipboard tool"):
        copy_text("fen")


def test_cli_falls_back_to_the_clipboard_when_no_path_is_given(
    clipboard, reference_image, capsys
):
    with Image.open(reference_image) as handle:
        clipboard(handle.convert("RGB"))
    assert main(["recognize"]) == 0
    assert capsys.readouterr().out.strip() == EXPECTED_FEN


def test_cli_reports_an_empty_clipboard_without_a_traceback(clipboard, capsys):
    clipboard(None)
    assert main(["recognize"]) == 1
    assert "clipboard" in capsys.readouterr().err
