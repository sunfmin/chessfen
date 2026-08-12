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

/* ------------------------------------------------------------------- rules  */

/*
  Rules Queries are stateless: every call takes the starting FEN plus the moves
  played from it and replays them. The Game lives in Swift; nothing is cached
  here, so these calls can never race with a running search (docs/adr/0003).
*/

/* Stockfish's own piece-type numbering, so nothing has to be renumbered. */
typedef enum {
    CF_PIECE_NONE = 0,
    CF_PAWN       = 1,
    CF_KNIGHT     = 2,
    CF_BISHOP     = 3,
    CF_ROOK       = 4,
    CF_QUEEN      = 5,
    CF_KING       = 6
} CfPieceType;

typedef struct {
    int32_t from;
    /* Where the piece lands *as the player sees it*: for castling this is g1/c1,
       not the rook's square that Stockfish encodes internally. */
    int32_t to;
    int32_t piece;      /* CfPieceType of the mover     */
    int32_t promotion;  /* CfPieceType or CF_PIECE_NONE */
    bool    isCapture;
    bool    isEnPassant;
    bool    isCastling;
    bool    givesCheck;
    bool    isCheckmate; /* the opponent has no legal reply to it */
    char    uci[8];      /* "e2e4", "e7e8q", "e1g1" */
} CfMove;

typedef enum {
    CF_ONGOING = 0,
    CF_CHECKMATE,
    CF_STALEMATE,
    CF_DRAW_FIFTY_MOVE,
    CF_DRAW_REPETITION,
    /* Insufficient *mating* material, the practical rule: bare kings, king and a
       single minor, or king and bishop each with both bishops on one colour. */
    CF_DRAW_INSUFFICIENT_MATERIAL
} CfOutcome;

#define CF_MAX_FEN 128
#define CF_MAX_CHECKERS 4

typedef struct {
    char    fen[CF_MAX_FEN];
    int32_t sideToMove; /* 0 white, 1 black */
    bool    inCheck;
    int32_t checkers[CF_MAX_CHECKERS]; /* CF_NO_SQUARE-padded */
    int32_t outcome;                   /* CfOutcome */
    int32_t halfmoveClock;
    int32_t fullmoveNumber;
    int32_t legalMoveCount;
} CfGameState;

/* Both return false when the FEN fails validation or a move does not parse as
   legal in the position it is played from. */
bool cf_game_state(const char       *startFen,
                   const char *const *moves,
                   int32_t            moveCount,
                   CfGameState       *out);

/* Writes at most `capacity` moves and returns how many exist, which may exceed
   `capacity`; 218 is the most any position can have. */
int32_t cf_legal_moves(const char       *startFen,
                       const char *const *moves,
                       int32_t            moveCount,
                       CfMove            *out,
                       int32_t            capacity);

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
