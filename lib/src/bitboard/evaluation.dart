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
  final white_ = _materialPstWhitePov(p) + _extendedWhitePov(p);
  return p.turn == white ? white_ : -white_;
}

/// Material + piece-square tables only. Kept as the A/B baseline for the extra
/// terms in [evaluatePosition] (self-play verification).
int evaluateMaterialPst(Position p) {
  final white_ = _materialPstWhitePov(p);
  return p.turn == white ? white_ : -white_;
}


/// Material + PST, always from White's point of view.
int _materialPstWhitePov(Position p) {
  var score = 0;

  var nonPawnMaterial = 0;
  for (final t in [knight, bishop, rook, queen]) {
    nonPawnMaterial +=
        popcount(p.pieces[white][t] | p.pieces[black][t]) * pieceValue[t];
  }
  final kingTable =
      nonPawnMaterial < 1300 ? _kingEndgameTable : _kingMiddlegameTable;

  for (var type = pawn; type <= king; type++) {
    final table = type == king ? kingTable : _pieceTables[type];
    final v = pieceValue[type];
    var wbb = p.pieces[white][type];
    while (wbb != 0) {
      final sq = lsb(wbb);
      wbb &= wbb - 1;
      score += v + table[_whiteIdx(sq)];
    }
    var bbb = p.pieces[black][type];
    while (bbb != 0) {
      final sq = lsb(bbb);
      bbb &= bbb - 1;
      score -= v + table[_blackIdx(sq)];
    }
  }
  return score;
}

// ---- Extended terms (White's point of view) --------------------------------

const int _bishopPairBonus = 30;
const int _doubledPawnPenalty = 12;
const int _isolatedPawnPenalty = 15;
// Passed-pawn bonus by the pawn's rank from its own side (rank 1..7).
const List<int> _passedByRank = [0, 8, 12, 20, 34, 55, 90, 0];

// Bishop pair + pawn structure. A mobility term was tried but dropped: it made
// the eval ~40% slower for no net gain under a time budget (the shallower
// search it caused cancelled its per-node value in self-play).
int _extendedWhitePov(Position p) {
  return _bishopPairWhitePov(p) + _pawnStructureWhitePov(p);
}

int _bishopPairWhitePov(Position p) {
  var s = 0;
  if (popcount(p.pieces[white][bishop]) >= 2) s += _bishopPairBonus;
  if (popcount(p.pieces[black][bishop]) >= 2) s -= _bishopPairBonus;
  return s;
}

int _pawnStructureWhitePov(Position p) {
  final wp = p.pieces[white][pawn];
  final bp = p.pieces[black][pawn];
  var s = 0;

  // Doubled + isolated (both colors).
  for (var f = 0; f < 8; f++) {
    final wOnFile = popcount(wp & _fileBb[f]);
    if (wOnFile > 1) s -= _doubledPawnPenalty * (wOnFile - 1);
    if (wOnFile > 0 && (wp & _adjFiles[f]) == 0) s -= _isolatedPawnPenalty;

    final bOnFile = popcount(bp & _fileBb[f]);
    if (bOnFile > 1) s += _doubledPawnPenalty * (bOnFile - 1);
    if (bOnFile > 0 && (bp & _adjFiles[f]) == 0) s += _isolatedPawnPenalty;
  }

  // Passed pawns.
  var bb = wp;
  while (bb != 0) {
    final sq = lsb(bb);
    bb &= bb - 1;
    if ((_whitePassed[sq] & bp) == 0) s += _passedByRank[sq >> 3];
  }
  bb = bp;
  while (bb != 0) {
    final sq = lsb(bb);
    bb &= bb - 1;
    if ((_blackPassed[sq] & wp) == 0) s -= _passedByRank[7 - (sq >> 3)];
  }
  return s;
}

// File / passed-pawn masks, built once.
final List<int> _fileBb = List.generate(8, (f) {
  var b = 0;
  for (var r = 0; r < 8; r++) {
    b |= 1 << (r * 8 + f);
  }
  return b;
});
final List<int> _adjFiles = List.generate(
    8, (f) => (f > 0 ? _fileBb[f - 1] : 0) | (f < 7 ? _fileBb[f + 1] : 0));

final List<int> _whitePassed = List.generate(64, (sq) => _passedMask(sq, true));
final List<int> _blackPassed = List.generate(64, (sq) => _passedMask(sq, false));

int _passedMask(int sq, bool forWhite) {
  final f = sq & 7, r = sq >> 3;
  var b = 0;
  for (var ff = f - 1; ff <= f + 1; ff++) {
    if (ff < 0 || ff > 7) continue;
    if (forWhite) {
      for (var rr = r + 1; rr < 8; rr++) {
        b |= 1 << (rr * 8 + ff);
      }
    } else {
      for (var rr = r - 1; rr >= 0; rr--) {
        b |= 1 << (rr * 8 + ff);
      }
    }
  }
  return b;
}
