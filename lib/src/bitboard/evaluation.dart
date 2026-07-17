// Bitboard evaluation — material + piece-square tables + endgame king table.
//
// Faithful port of the chess-package evaluation so the bitboard engine plays
// the same strength/style. NATIVE ONLY (see attacks.dart).

import 'attacks.dart';
import 'position.dart';

/// Centipawn material values, indexed by piece type (pawn..king).
const List<int> pieceValue = [100, 320, 330, 500, 900, 20000];

// Piece-square tables, written from White's view with a8 at index 0 (the
// board seen from above). Access is remapped from LERF squares below.
const List<int> _pawnTable = [0,0,0,0,0,0,0,0,50,50,50,50,50,50,50,50,10,10,20,30,30,20,10,10,5,5,10,25,25,10,5,5,0,0,0,20,20,0,0,0,5,-5,-10,0,0,-10,-5,5,5,10,10,-20,-20,10,10,5,0,0,0,0,0,0,0,0];
const List<int> _knightTable = [-50,-40,-30,-30,-30,-30,-40,-50,-40,-20,0,0,0,0,-20,-40,-30,0,10,15,15,10,0,-30,-30,5,15,20,20,15,5,-30,-30,0,15,20,20,15,0,-30,-30,5,10,15,15,10,5,-30,-40,-20,0,5,5,0,-20,-40,-50,-40,-30,-30,-30,-30,-40,-50];
const List<int> _bishopTable = [-20,-10,-10,-10,-10,-10,-10,-20,-10,0,0,0,0,0,0,-10,-10,0,10,10,10,10,0,-10,-10,5,5,10,10,5,5,-10,-10,0,10,10,10,10,0,-10,-10,10,10,10,10,10,10,-10,-10,5,0,0,0,0,5,-10,-20,-10,-10,-10,-10,-10,-10,-20];
const List<int> _rookTable = [0,0,0,0,0,0,0,0,5,10,10,10,10,10,10,5,-5,0,0,0,0,0,0,-5,-5,0,0,0,0,0,0,-5,-5,0,0,0,0,0,0,-5,-5,0,0,0,0,0,0,-5,-5,0,0,0,0,0,0,-5,0,0,0,5,5,0,0,0];
const List<int> _queenTable = [-20,-10,-10,-5,-5,-10,-10,-20,-10,0,0,0,0,0,0,-10,-10,0,5,5,5,5,0,-10,-5,0,5,5,5,5,0,-5,0,0,5,5,5,5,0,-5,-10,5,5,5,5,5,0,-10,-10,0,5,0,0,0,0,-10,-20,-10,-10,-5,-5,-10,-10,-20];
const List<int> _kingMiddlegameTable = [-30,-40,-40,-50,-50,-40,-40,-30,-30,-40,-40,-50,-50,-40,-40,-30,-30,-40,-40,-50,-50,-40,-40,-30,-30,-40,-40,-50,-50,-40,-40,-30,-20,-30,-30,-40,-40,-30,-30,-20,-10,-20,-20,-20,-20,-20,-20,-10,20,20,0,0,0,0,20,20,20,30,10,0,0,10,30,20];
const List<int> _kingEndgameTable = [-50,-40,-30,-20,-20,-30,-40,-50,-30,-20,-10,0,0,-10,-20,-30,-30,-10,20,30,30,20,-10,-30,-30,-10,30,40,40,30,-10,-30,-30,-10,30,40,40,30,-10,-30,-30,-10,20,30,30,20,-10,-30,-30,-30,0,0,0,0,-30,-30,-50,-30,-30,-30,-30,-30,-30,-50];

const List<List<int>> _pieceTables = [
  _pawnTable,
  _knightTable,
  _bishopTable,
  _rookTable,
  _queenTable,
  // king handled separately (middlegame vs endgame)
];

// Table index for a White piece on LERF square [sq] (a8-first layout).
int _whiteIdx(int sq) => (7 - (sq >> 3)) * 8 + (sq & 7);
// Vertical mirror for a Black piece.
int _blackIdx(int sq) => (sq >> 3) * 8 + (sq & 7);

/// Static evaluation from the side-to-move's perspective, in centipawns.
///
/// No terminal/draw detection here — the search owns that (it scores mate and
/// stalemate from an empty move list and handles the 50-move rule / repetition).
int evaluatePosition(Position p) {
  var whiteScore = 0;
  var blackScore = 0;

  // Non-pawn, non-king material to pick the king table.
  var nonPawnMaterial = 0;
  for (final t in [knight, bishop, rook, queen]) {
    nonPawnMaterial +=
        popcount(p.pieces[white][t] | p.pieces[black][t]) * pieceValue[t];
  }
  final isEndgame = nonPawnMaterial < 1300;
  final kingTable = isEndgame ? _kingEndgameTable : _kingMiddlegameTable;

  for (var type = pawn; type <= king; type++) {
    final table = type == king ? kingTable : _pieceTables[type];
    final v = pieceValue[type];

    var wbb = p.pieces[white][type];
    while (wbb != 0) {
      final sq = lsb(wbb);
      wbb &= wbb - 1;
      whiteScore += v + table[_whiteIdx(sq)];
    }
    var bbb = p.pieces[black][type];
    while (bbb != 0) {
      final sq = lsb(bbb);
      bbb &= bbb - 1;
      blackScore += v + table[_blackIdx(sq)];
    }
  }

  final score = whiteScore - blackScore;
  return p.turn == white ? score : -score;
}
