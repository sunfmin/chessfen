#include "include/chessfen_bridge.h"

#include <cctype>
#include <cstring>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#include "stockfish/bitboard.h"
#include "stockfish/movegen.h"
#include "stockfish/perft.h"
#include "stockfish/position.h"
#include "stockfish/types.h"

using namespace Stockfish;

// ---------------------------------------------------------------- lifecycle

void cf_global_init(void) {
    static std::once_flag once;
    std::call_once(once, [] {
        Bitboards::init();
        Position::init();
    });
}

// ------------------------------------------------------------- FEN validity

namespace {

struct Verdict {
    CfFenVerdict value;

    explicit Verdict(CfFenIssue issue = CF_FEN_OK, int colour = -1) {
        value.issue  = issue;
        value.colour = colour;
        for (int i = 0; i < CF_MAX_MARKED_SQUARES; ++i)
            value.squares[i] = CF_NO_SQUARE;
    }

    Verdict& mark(int square) {
        for (int i = 0; i < CF_MAX_MARKED_SQUARES; ++i)
            if (value.squares[i] == CF_NO_SQUARE)
            {
                value.squares[i] = square;
                break;
            }
        return *this;
    }
};

// Everything the placement field says, in a form the later rules can question.
struct Placement {
    int  pieceCount[2]  = {0, 0};
    int  pawnCount[2]   = {0, 0};
    int  kingSquare[2]  = {CF_NO_SQUARE, CF_NO_SQUARE};
    int  extraKing[2]   = {CF_NO_SQUARE, CF_NO_SQUARE};
    bool rookOnHome[2]  = {false, false};  // any rook on that colour's rank 1/8
    std::vector<int> pawnsOnBackRank;
};

constexpr int squareOf(int file, int rank) { return rank * 8 + file; }

// Parses the placement field only. Pure string work: nothing here may hand a
// half-trusted FEN to Stockfish, because that is the thing being guarded.
bool parsePlacement(const std::string& field, Placement& out, Verdict& bad) {
    int file = 0, rank = 7;

    for (char token : field)
    {
        if (token == '/')
        {
            if (file != 8)
            {
                bad = Verdict(CF_FEN_BAD_RANK_WIDTH);
                return false;
            }
            if (--rank < 0)
            {
                bad = Verdict(CF_FEN_BAD_RANK_COUNT);
                return false;
            }
            file = 0;
            continue;
        }

        if (token >= '1' && token <= '8')
        {
            file += token - '0';
            if (file > 8)
            {
                bad = Verdict(CF_FEN_BAD_RANK_WIDTH);
                return false;
            }
            continue;
        }

        const char  upper  = char(std::toupper(token));
        const int   colour = std::islower(token) ? 1 : 0;
        const char* known  = "PNBRQK";
        if (!std::strchr(known, upper))
        {
            bad = Verdict(CF_FEN_BAD_PIECE_CHAR);
            return false;
        }
        if (file > 7)
        {
            bad = Verdict(CF_FEN_BAD_RANK_WIDTH);
            return false;
        }

        const int square = squareOf(file, rank);
        out.pieceCount[colour]++;

        if (upper == 'P')
        {
            out.pawnCount[colour]++;
            if (rank == 0 || rank == 7)
                out.pawnsOnBackRank.push_back(square);
        }
        else if (upper == 'K')
        {
            if (out.kingSquare[colour] == CF_NO_SQUARE)
                out.kingSquare[colour] = square;
            else
                out.extraKing[colour] = square;
        }
        else if (upper == 'R')
        {
            if (rank == (colour == 0 ? 0 : 7))
                out.rookOnHome[colour] = true;
        }

        ++file;
    }

    if (file != 8)
    {
        bad = Verdict(CF_FEN_BAD_RANK_WIDTH);
        return false;
    }
    if (rank != 0)
    {
        bad = Verdict(CF_FEN_BAD_RANK_COUNT);
        return false;
    }
    return true;
}

Verdict validate(const std::string& fen) {
    std::istringstream stream(fen);
    std::string placement, sideToMove, castling, enPassant;
    if (!(stream >> placement >> sideToMove >> castling >> enPassant))
        return Verdict(CF_FEN_MALFORMED);

    Placement board;
    Verdict   bad;
    if (!parsePlacement(placement, board, bad))
        return bad;

    for (int colour = 0; colour < 2; ++colour)
    {
        if (board.kingSquare[colour] == CF_NO_SQUARE)
            return Verdict(CF_FEN_MISSING_KING, colour);
        if (board.extraKing[colour] != CF_NO_SQUARE)
            return Verdict(CF_FEN_EXTRA_KING, colour)
              .mark(board.kingSquare[colour])
              .mark(board.extraKing[colour]);
        if (board.pieceCount[colour] > 16)
            return Verdict(CF_FEN_TOO_MANY_PIECES, colour);
        if (board.pawnCount[colour] > 8)
            return Verdict(CF_FEN_TOO_MANY_PAWNS, colour);
    }

    if (!board.pawnsOnBackRank.empty())
    {
        Verdict verdict(CF_FEN_PAWN_ON_BACK_RANK);
        for (int square : board.pawnsOnBackRank)
            verdict.mark(square);
        return verdict;
    }

    if (sideToMove != "w" && sideToMove != "b")
        return Verdict(CF_FEN_BAD_SIDE_TO_MOVE);

    if (castling != "-")
        for (char right : castling)
        {
            const int  colour   = std::islower(right) ? 1 : 0;
            const char upper    = char(std::toupper(right));
            const int  homeKing = colour == 0 ? squareOf(4, 0) : squareOf(4, 7);

            if (upper != 'K' && upper != 'Q')
                return Verdict(CF_FEN_BAD_CASTLING, colour);
            // Stockfish scans the home rank for a rook in a loop with no lower
            // bound; without one it reads off the board.
            if (!board.rookOnHome[colour])
                return Verdict(CF_FEN_CASTLING_WITHOUT_ROOK, colour);
            if (board.kingSquare[colour] != homeKing)
                return Verdict(CF_FEN_CASTLING_WITHOUT_KING, colour)
                  .mark(board.kingSquare[colour]);
        }

    if (enPassant != "-")
    {
        if (enPassant.size() != 2 || enPassant[0] < 'a' || enPassant[0] > 'h')
            return Verdict(CF_FEN_BAD_EN_PASSANT);
        const char wantedRank = sideToMove == "w" ? '6' : '3';
        if (enPassant[1] != wantedRank)
            return Verdict(CF_FEN_BAD_EN_PASSANT);
    }

    int halfmove = 0, fullmove = 1;
    if (stream >> halfmove)
    {
        if (halfmove < 0 || halfmove > 150)
            return Verdict(CF_FEN_BAD_CLOCK);
        if ((stream >> fullmove) && fullmove < 1)
            return Verdict(CF_FEN_BAD_CLOCK);
    }

    // Only now is the FEN safe to hand over: kings exist, castling rights have a
    // rook to find. The last rule needs a real Position to answer.
    cf_global_init();
    StateInfo state;
    Position  position;
    position.set(fen, false, &state);

    const Color mover  = position.side_to_move();
    const Color waiter = ~mover;
    if (position.attackers_to(position.square<KING>(waiter)) & position.pieces(mover))
        return Verdict(CF_FEN_SIDE_NOT_TO_MOVE_IN_CHECK, waiter == WHITE ? 0 : 1)
          .mark(int(position.square<KING>(waiter)));

    return Verdict();
}

}  // namespace

CfFenVerdict cf_validate_fen(const char *fen) {
    if (fen == nullptr)
        return Verdict(CF_FEN_MALFORMED).value;
    return validate(std::string(fen)).value;
}

// ------------------------------------------------------------------- perft

uint64_t cf_perft(const char *fen, int depth) {
    if (fen == nullptr || cf_validate_fen(fen).issue != CF_FEN_OK)
        return 0;

    cf_global_init();
    StateInfo state;
    Position  position;
    position.set(std::string(fen), false, &state);

    if (depth <= 0)
        return 1;
    // Stockfish's own perft<false> recurses without a floor at depth 1, and its
    // perft<true> prints every root move to stdout. Neither is wanted here.
    if (depth == 1)
        return MoveList<LEGAL>(position).size();
    return Benchmark::perft<false>(position, depth);
}
