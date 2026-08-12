/*
  A C ABI over the parts of Stockfish this app uses. Deliberately C and not C++
  interop: the callers are Swift, the values crossing are plain data, and a C
  surface keeps Stockfish's headers — and its concurrency — out of Swift's way.

  Stockfish is GPLv3, so this whole repository is (see docs/adr/0001).
*/

#ifndef CHESSFEN_BRIDGE_H
#define CHESSFEN_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Squares are 0..63 with a1 = 0, h1 = 7, a8 = 56 — Stockfish's own numbering. */
#define CF_NO_SQUARE (-1)

/* ---------------------------------------------------------------- lifecycle */

/* Idempotent; must be called before anything else here. */
void cf_global_init(void);

/* ------------------------------------------------------------- FEN validity */

/*
  Why this exists at all: Stockfish 18's Position::set does no validation. Its
  asserts vanish under NDEBUG, square<KING>() is undefined without exactly one
  king, and the castling parser scans for a rook with an unbounded loop that
  walks off the board when the FEN claims a right no rook can support. Every FEN
  is therefore vetted here before Stockfish is allowed to see it.
*/
typedef enum {
    CF_FEN_OK = 0,
    CF_FEN_MALFORMED,                  /* not enough fields, or junk in them   */
    CF_FEN_BAD_PIECE_CHAR,             /* placement field has an unknown glyph */
    CF_FEN_BAD_RANK_WIDTH,             /* a rank does not add up to 8 files    */
    CF_FEN_BAD_RANK_COUNT,             /* not 8 ranks                          */
    CF_FEN_TOO_MANY_PIECES,            /* >32 on the board, or >16 for a side  */
    CF_FEN_TOO_MANY_PAWNS,             /* >8 pawns for a side                  */
    CF_FEN_MISSING_KING,               /* a side has no king                   */
    CF_FEN_EXTRA_KING,                 /* a side has more than one king        */
    CF_FEN_PAWN_ON_BACK_RANK,          /* pawn on rank 1 or rank 8             */
    CF_FEN_BAD_SIDE_TO_MOVE,
    CF_FEN_BAD_CASTLING,               /* glyph outside KQkq-                  */
    CF_FEN_CASTLING_WITHOUT_ROOK,      /* the unbounded-loop hazard            */
    CF_FEN_CASTLING_WITHOUT_KING,      /* king not on its home square          */
    CF_FEN_BAD_EN_PASSANT,
    CF_FEN_BAD_CLOCK,
    CF_FEN_SIDE_NOT_TO_MOVE_IN_CHECK   /* also covers adjacent kings           */
} CfFenIssue;

#define CF_MAX_MARKED_SQUARES 8

/* `colour`: 0 white, 1 black, -1 when the issue belongs to neither.
   `squares`: the squares worth highlighting, CF_NO_SQUARE-padded. */
typedef struct {
    CfFenIssue issue;
    int32_t    colour;
    int32_t    squares[CF_MAX_MARKED_SQUARES];
} CfFenVerdict;

CfFenVerdict cf_validate_fen(const char *fen);

/* ------------------------------------------------------------------- perft  */

/*
  Leaf count of the legal move tree `depth` plies below `fen`. Returns 0 when the
  FEN does not validate. Present because it is the cheapest possible proof that
  the vendored engine is really linked and really generating moves.
*/
uint64_t cf_perft(const char *fen, int depth);

#ifdef __cplusplus
}
#endif
#endif /* CHESSFEN_BRIDGE_H */
