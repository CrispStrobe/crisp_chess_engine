// Bitboard primitives and attack tables.
//
// NATIVE ONLY. Bitboards are 64-bit and this file uses 64-bit int literals and
// operations, which do not work under dart2js (web ints are doubles). Nothing
// on the web code path may import this library — see lib/bitboard.dart.
//
// Square indexing is little-endian rank-file (LERF): a1=0, b1=1, ... h1=7,
// a2=8, ... h8=63. file = sq & 7, rank = sq >> 3.

/// Piece type indices.
const int pawn = 0;
const int knight = 1;
const int bishop = 2;
const int rook = 3;
const int queen = 4;
const int king = 5;

/// Colors.
const int white = 0;
const int black = 1;

/// All-ones 64-bit mask (== -1 as a signed VM int).
const int fullBoard = -1;

const int fileABb = 0x0101010101010101;
const int fileHBb = 0x8080808080808080;

/// Number of set bits. Kernighan's method; fine for eval-frequency use.
int popcount(int bb) {
  var n = 0;
  while (bb != 0) {
    bb &= bb - 1;
    n++;
  }
  return n;
}

// De Bruijn bitscan. Works on unsigned 64-bit values held in signed VM ints
// (bit 63 makes the value negative, so we never rely on sign or bitLength).
const int _debruijn64 = 0x03f79d71b4cb0a89;
const List<int> _index64 = [
  0, 47, 1, 56, 48, 27, 2, 60, //
  57, 49, 41, 37, 28, 16, 3, 61,
  54, 58, 35, 52, 50, 42, 21, 44,
  38, 32, 29, 23, 17, 11, 4, 62,
  46, 55, 26, 59, 40, 36, 15, 53,
  34, 51, 20, 43, 31, 22, 10, 45,
  25, 39, 14, 33, 19, 30, 9, 24,
  13, 18, 8, 12, 7, 6, 5, 63,
];

/// Index of the least-significant set bit. [bb] must be non-zero.
///
/// Uses the trailing-ones mask `bb ^ (bb-1)` (all bits up to and including the
/// LSB), which is the form [_index64] is built for — the same table the folded
/// [msb] uses. (An isolated `bb & -bb` would need a different De Bruijn table.)
int lsb(int bb) => _index64[(((bb ^ (bb - 1)) * _debruijn64) >>> 58) & 63];

/// Index of the most-significant set bit. [bb] must be non-zero.
int msb(int bb) {
  bb |= bb >>> 1;
  bb |= bb >>> 2;
  bb |= bb >>> 4;
  bb |= bb >>> 8;
  bb |= bb >>> 16;
  bb |= bb >>> 32;
  return _index64[((bb * _debruijn64) >>> 58) & 63];
}

/// Pop the least-significant set bit, returning its index. Mutates via return:
/// callers use `sq = lsb(bb); bb &= bb - 1;`.

// Attack tables, built once at load.
final List<int> knightAttacks = _buildKnightAttacks();
final List<int> kingAttacks = _buildKingAttacks();
// pawnAttacks[color][square]
final List<List<int>> pawnAttacks = _buildPawnAttacks();
// rayAttacks[direction][square]; directions below.
final List<List<int>> _rayAttacks = _buildRayAttacks();

// Ray directions as (fileDelta, rankDelta). Positive rays scan forward (lsb),
// negative rays scan backward (msb).
const int _dirN = 0, _dirE = 1, _dirNE = 2, _dirNW = 3;
const int _dirS = 4, _dirW = 5, _dirSE = 6, _dirSW = 7;
const List<List<int>> _dirDelta = [
  [0, 1], // N
  [1, 0], // E
  [1, 1], // NE
  [-1, 1], // NW
  [0, -1], // S
  [-1, 0], // W
  [1, -1], // SE
  [-1, -1], // SW
];
const List<bool> _dirPositive = [
  true, true, true, true, // N, E, NE, NW scan up (lsb)
  false, false, false, false, // S, W, SE, SW scan down (msb)
];

int _bit(int sq) => 1 << sq;

List<int> _buildKnightAttacks() {
  const deltas = [
    [1, 2], [2, 1], [2, -1], [1, -2], //
    [-1, -2], [-2, -1], [-2, 1], [-1, 2],
  ];
  return _buildStepAttacks(deltas);
}

List<int> _buildKingAttacks() {
  const deltas = [
    [0, 1], [1, 1], [1, 0], [1, -1], //
    [0, -1], [-1, -1], [-1, 0], [-1, 1],
  ];
  return _buildStepAttacks(deltas);
}

List<int> _buildStepAttacks(List<List<int>> deltas) {
  final table = List<int>.filled(64, 0);
  for (var sq = 0; sq < 64; sq++) {
    final f = sq & 7, r = sq >> 3;
    var bb = 0;
    for (final d in deltas) {
      final nf = f + d[0], nr = r + d[1];
      if (nf >= 0 && nf < 8 && nr >= 0 && nr < 8) {
        bb |= _bit(nr * 8 + nf);
      }
    }
    table[sq] = bb;
  }
  return table;
}

List<List<int>> _buildPawnAttacks() {
  final w = List<int>.filled(64, 0);
  final b = List<int>.filled(64, 0);
  for (var sq = 0; sq < 64; sq++) {
    final f = sq & 7, r = sq >> 3;
    // White captures go up a rank (NE, NW).
    if (r < 7) {
      if (f > 0) w[sq] |= _bit(sq + 7);
      if (f < 7) w[sq] |= _bit(sq + 9);
    }
    // Black captures go down a rank (SE, SW).
    if (r > 0) {
      if (f > 0) b[sq] |= _bit(sq - 9);
      if (f < 7) b[sq] |= _bit(sq - 7);
    }
  }
  return [w, b];
}

List<List<int>> _buildRayAttacks() {
  final rays = List.generate(8, (_) => List<int>.filled(64, 0));
  for (var dir = 0; dir < 8; dir++) {
    final df = _dirDelta[dir][0], dr = _dirDelta[dir][1];
    for (var sq = 0; sq < 64; sq++) {
      var f = (sq & 7) + df, r = (sq >> 3) + dr;
      var bb = 0;
      while (f >= 0 && f < 8 && r >= 0 && r < 8) {
        bb |= _bit(r * 8 + f);
        f += df;
        r += dr;
      }
      rays[dir][sq] = bb;
    }
  }
  return rays;
}

/// Classical ray attack along [dir] from [sq] given [occ]upancy: the ray, cut
/// off at (and including) the first blocker.
int _rayAttack(int dir, int sq, int occ) {
  final ray = _rayAttacks[dir][sq];
  final blockers = ray & occ;
  if (blockers == 0) return ray;
  final blockSq = _dirPositive[dir] ? lsb(blockers) : msb(blockers);
  return ray ^ _rayAttacks[dir][blockSq];
}

/// Bishop attacks from [sq] given full-board [occ]upancy.
int bishopAttacks(int sq, int occ) =>
    _rayAttack(_dirNE, sq, occ) |
    _rayAttack(_dirNW, sq, occ) |
    _rayAttack(_dirSE, sq, occ) |
    _rayAttack(_dirSW, sq, occ);

/// Rook attacks from [sq] given full-board [occ]upancy.
int rookAttacks(int sq, int occ) =>
    _rayAttack(_dirN, sq, occ) |
    _rayAttack(_dirE, sq, occ) |
    _rayAttack(_dirS, sq, occ) |
    _rayAttack(_dirW, sq, occ);

/// Queen attacks from [sq] given full-board [occ]upancy.
int queenAttacks(int sq, int occ) => bishopAttacks(sq, occ) | rookAttacks(sq, occ);
