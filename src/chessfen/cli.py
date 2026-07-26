"""Command line front end: ``chessfen recognize IMAGE`` and ``chessfen render FEN``."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import chess

from .clipboard import ClipboardImageError, clipboard_image
from .geometry import BoardNotFoundError
from .recognize import Castling, Orientation, Recognition, recognize
from .render import RenderOptions, render_png


def main(argv: list[str] | None = None) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    try:
        match args.command:
            case "recognize":
                return _recognize(args)
            case "render":
                return _render(args)
            case _:  # pragma: no cover - argparse rejects anything else
                parser.error(f"unknown command {args.command!r}")
                return 2
    except (BoardNotFoundError, ClipboardImageError, ValueError) as error:
        print(f"chessfen: {error}", file=sys.stderr)
        return 1


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="chessfen", description="Chess board image <-> FEN"
    )
    commands = parser.add_subparsers(dest="command", required=True)

    read = commands.add_parser("recognize", help="read a FEN out of a board image")
    read.add_argument(
        "image",
        type=Path,
        nargs="?",
        help="board image; omit to read the image from the clipboard",
    )
    read.add_argument(
        "--turn",
        choices=("w", "b"),
        default="w",
        help="side to move; an image cannot show it (default: w)",
    )
    read.add_argument(
        "--orientation",
        type=Orientation,
        choices=tuple(Orientation),
        default=Orientation.AUTO,
        help="which side is at the bottom (default: auto)",
    )
    read.add_argument(
        "--castling",
        type=Castling,
        choices=tuple(Castling),
        default=Castling.AUTO,
        help="castling field: infer from home squares, or leave empty (default: auto)",
    )
    read.add_argument("--board", action="store_true", help="also print an ASCII board")
    read.add_argument("--json", action="store_true", help="print a JSON report")

    write = commands.add_parser("render", help="draw a board image from a FEN")
    write.add_argument("fen")
    write.add_argument("-o", "--output", type=Path, required=True)
    write.add_argument("--size", type=int, default=480)
    write.add_argument("--coordinates", action="store_true")
    write.add_argument("--flipped", action="store_true")
    return parser


def _recognize(args: argparse.Namespace) -> int:
    source = args.image if args.image is not None else clipboard_image()
    result = recognize(
        source,
        turn=chess.WHITE if args.turn == "w" else chess.BLACK,
        orientation=args.orientation,
        castling=args.castling,
    )
    if args.json:
        print(json.dumps(_report(result), indent=2))
        return 0
    print(result.fen)
    if args.board:
        print(result.board.unicode(borders=True, empty_square="."))
    for square, verdict in result.shaky.items():
        print(
            f"chessfen: low confidence on {chess.square_name(square)}: "
            f"{verdict.piece} score={verdict.score:.2f} margin={verdict.margin:.2f}",
            file=sys.stderr,
        )
    return 0


def _report(result: Recognition) -> dict[str, object]:
    return {
        "fen": result.fen,
        "orientation": str(result.orientation),
        "board": {
            "left": result.rect.left,
            "top": result.rect.top,
            "size": result.rect.size,
        },
        "squares": [
            {
                "square": chess.square_name(square),
                "piece": verdict.piece.symbol() if verdict.piece else None,
                "score": round(verdict.score, 4),
                "margin": round(verdict.margin, 4),
                "confident": verdict.confident,
            }
            for square, verdict in sorted(result.verdicts.items())
            if verdict.piece is not None or not verdict.confident
        ],
    }


def _render(args: argparse.Namespace) -> int:
    board = chess.Board(args.fen)
    path = render_png(
        board,
        args.output,
        RenderOptions(
            size=args.size,
            coordinates=args.coordinates,
            flipped=args.flipped,
        ),
    )
    print(path)
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
