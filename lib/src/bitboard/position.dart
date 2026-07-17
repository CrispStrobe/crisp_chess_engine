// Bitboard position: state, make/unmake, move generation, FEN, perft.
//
// NATIVE ONLY (64-bit). See attacks.dart.

import 'attacks.dart';

// ---- Move encoding -----------------------------------------------------------
// A move is packed into an int: from(6) | to(6)<<6 | flag(4)<<12.
// The 4-bit flag follows the classic chessprogramming.org codes:
//   0 quiet          1 double push     2 king castle    3 queen castle
//   4 capture        5 ep capture
//   8..11  promotion to knight/bishop/rook/queen (quiet)
//  12..15  promotion to knight/bishop/rook/queen (capture)
// Bit 2 (0x4) marks a capture; bit 3 (0x8) marks a promotion.

const int flagQuiet = 0;
const int flagDoublePush = 1;
const int flagKingCastle = 2;
const int flagQueenCastle = 3;
const int flagCapture = 4;
const int flagEpCapture = 5;
const int flagPromoKnight = 8;
const int flagPromoQueen = 11;
const int flagPromoCaptureKnight = 12;

int encodeMove(int from, int to, int flag) => from | (to << 6) | (flag << 12);
int moveFrom(int m) => m & 0x3f;
int moveTo(int m) => (m >> 6) & 0x3f;
int moveFlag(int m) => (m >> 12) & 0xf;
bool moveIsCapture(int m) => (moveFlag(m) & 0x4) != 0;
bool moveIsPromotion(int m) => (moveFlag(m) & 0x8) != 0;
bool moveIsEnPassant(int m) => moveFlag(m) == flagEpCapture;
bool moveIsCastle(int m) {
  final f = moveFlag(m);
  return f == flagKingCastle || f == flagQueenCastle;
}

/// Promotion piece type (knight..queen) for a promotion move.
int movePromoType(int m) => knight + (moveFlag(m) & 0x3);

// Castling-rights bits.
const int castleWK = 1, castleWQ = 2, castleBK = 4, castleBQ = 8;

// Named squares.
const int _a1 = 0, _c1 = 2, _d1 = 3, _e1 = 4, _f1 = 5, _g1 = 6, _h1 = 7;
const int _a8 = 56, _c8 = 58, _d8 = 59, _e8 = 60, _f8 = 61, _g8 = 62, _h8 = 63;

/// Moving from/to a square clears these castling rights (king or rook left its
/// home, or a home rook was captured).
final List<int> _castleClear = _buildCastleClear();
List<int> _buildCastleClear() {
  final t = List<int>.filled(64, 0xf);
  t[_e1] = 0xf & ~(castleWK | castleWQ);
  t[_h1] = 0xf & ~castleWK;
  t[_a1] = 0xf & ~castleWQ;
  t[_e8] = 0xf & ~(castleBK | castleBQ);
  t[_h8] = 0xf & ~castleBK;
  t[_a8] = 0xf & ~castleBQ;
  return t;
}

const String startposFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// Undo record pushed on make, popped on unmake.
class _Undo {
  final int move;
  final int capturedType; // piece type captured, or -1
  final int castling;
  final int epSquare;
  final int halfmove;
  _Undo(this.move, this.capturedType, this.castling, this.epSquare,
      this.halfmove);
}

class Position {
  // pieces[color][type] bitboards.
  final List<List<int>> pieces =
      List.generate(2, (_) => List<int>.filled(6, 0));
  // Occupancy per color and combined.
  final List<int> occ = [0, 0];
  int occAll = 0;
  // mailbox[sq] = piece type (0..5) or -1 if empty.
  final List<int> mailbox = List<int>.filled(64, -1);

  int turn = white;
  int castling = 0;
  int epSquare = -1; // -1 if none
  int halfmove = 0;
  int fullmove = 1;

  final List<_Undo> _undo = [];

  Position();
  factory Position.startpos() => Position.fromFen(startposFen);

  factory Position.fromFen(String fen) {
    final p = Position();
    final parts = fen.trim().split(RegExp(r'\s+'));
    final placement = parts[0];
    var rank = 7, file = 0;
    for (final ch in placement.split('')) {
      if (ch == '/') {
        rank--;
        file = 0;
      } else if (RegExp(r'[1-8]').hasMatch(ch)) {
        file += int.parse(ch);
      } else {
        final color = ch == ch.toUpperCase() ? white : black;
        final type = _pieceTypeFromChar(ch.toLowerCase());
        p._addPiece(color, type, rank * 8 + file);
        file++;
      }
    }
    p.turn = (parts.length > 1 && parts[1] == 'b') ? black : white;
    p.castling = 0;
    if (parts.length > 2 && parts[2] != '-') {
      for (final c in parts[2].split('')) {
        switch (c) {
          case 'K':
            p.castling |= castleWK;
          case 'Q':
            p.castling |= castleWQ;
          case 'k':
            p.castling |= castleBK;
          case 'q':
            p.castling |= castleBQ;
        }
      }
    }
    p.epSquare = (parts.length > 3 && parts[3] != '-')
        ? _squareFromName(parts[3])
        : -1;
    p.halfmove = parts.length > 4 ? int.tryParse(parts[4]) ?? 0 : 0;
    p.fullmove = parts.length > 5 ? int.tryParse(parts[5]) ?? 1 : 1;
    return p;
  }

  void _addPiece(int color, int type, int sq) {
    final b = 1 << sq;
    pieces[color][type] |= b;
    occ[color] |= b;
    occAll |= b;
    mailbox[sq] = type;
  }

  int get kingSquare => lsb(pieces[turn][king]);
  int _kingSquareOf(int color) => lsb(pieces[color][king]);

  /// Is [sq] attacked by any piece of [byColor], given current occupancy?
  bool isSquareAttacked(int sq, int byColor) {
    // Pawns: a square is attacked by byColor pawns from the opposite pawn's
    // capture pattern.
    if ((pawnAttacks[byColor ^ 1][sq] & pieces[byColor][pawn]) != 0) return true;
    if ((knightAttacks[sq] & pieces[byColor][knight]) != 0) return true;
    if ((kingAttacks[sq] & pieces[byColor][king]) != 0) return true;
    final bishopsQueens = pieces[byColor][bishop] | pieces[byColor][queen];
    if ((bishopAttacks(sq, occAll) & bishopsQueens) != 0) return true;
    final rooksQueens = pieces[byColor][rook] | pieces[byColor][queen];
    if ((rookAttacks(sq, occAll) & rooksQueens) != 0) return true;
    return false;
  }

  bool get inCheck => isSquareAttacked(_kingSquareOf(turn), turn ^ 1);

  /// After [makeMove], whether the side that just moved left its own king safe
  /// (i.e. the move was legal). Cheap legality filter for search/perft.
  bool get moverKingSafe =>
      !isSquareAttacked(_kingSquareOf(turn ^ 1), turn);

  static const List<int> _seeValues = [100, 320, 330, 500, 900, 20000];

  /// All pieces of either color attacking [sq] given occupancy [occ].
  int _attackersTo(int sq, int occ) {
    final bishopsQueens = pieces[white][bishop] |
        pieces[black][bishop] |
        pieces[white][queen] |
        pieces[black][queen];
    final rooksQueens = pieces[white][rook] |
        pieces[black][rook] |
        pieces[white][queen] |
        pieces[black][queen];
    return (pawnAttacks[black][sq] & pieces[white][pawn]) |
        (pawnAttacks[white][sq] & pieces[black][pawn]) |
        (knightAttacks[sq] & (pieces[white][knight] | pieces[black][knight])) |
        (kingAttacks[sq] & (pieces[white][king] | pieces[black][king])) |
        (bishopAttacks(sq, occ) & bishopsQueens) |
        (rookAttacks(sq, occ) & rooksQueens);
  }

  int _leastValuableAttacker(int attackers, int side) {
    for (var t = pawn; t <= king; t++) {
      final bb = attackers & pieces[side][t];
      if (bb != 0) return lsb(bb);
    }
    return -1;
  }

  /// Static Exchange Evaluation: the material a capture [move] wins or loses
  /// after the full sequence of optimal recaptures on the target square, in
  /// centipawns from the moving side's view. Negative means a losing capture.
  int see(int move) {
    final to = moveTo(move);
    final from = moveFrom(move);
    var occ = occAll;
    int targetType;
    if (moveIsEnPassant(move)) {
      targetType = pawn;
      final capSq = turn == white ? to - 8 : to + 8;
      occ ^= 1 << capSq; // remove ep-captured pawn so x-rays are correct
    } else {
      final t = mailbox[to];
      if (t == -1) return 0; // not a capture
      targetType = t;
    }

    final gain = List<int>.filled(32, 0);
    gain[0] = _seeValues[targetType];
    var attackerType = mailbox[from];
    var fromBit = 1 << from;
    var side = turn;
    var d = 0;

    // Run the full swap sequence (no early pruning — it's subtle and SEE
    // sequences on one square are short, so correctness wins).
    while (true) {
      d++;
      gain[d] = _seeValues[attackerType] - gain[d - 1];
      occ ^= fromBit; // the attacker that just captured leaves the board
      side ^= 1;
      final attackers = _attackersTo(to, occ) & occ;
      final sq = _leastValuableAttacker(attackers, side);
      if (sq < 0) break;
      fromBit = 1 << sq;
      attackerType = mailbox[sq];
    }
    while (--d > 0) {
      gain[d - 1] = -(-gain[d - 1] > gain[d] ? -gain[d - 1] : gain[d]);
    }
    return gain[0];
  }

  /// A full 64-bit position key (native ints), folding all piece bitboards plus
  /// side-to-move, castling rights and the en-passant square. Cheap — no FEN
  /// rebuild — and collisions are negligible for a per-search table.
  int hash() {
    var h = turn == white ? 0x9e3779b97f4a7c15 : 0x1c69b3f74ac4ae35;
    for (var c = 0; c < 2; c++) {
      for (var t = 0; t < 6; t++) {
        h = _mix(h ^ pieces[c][t]) + (c * 6 + t + 1);
      }
    }
    h ^= castling * 0x100000001b3;
    h ^= epSquare + 1;
    return _mix(h);
  }

  static int _mix(int x) {
    x ^= x >>> 30;
    x *= 0xbf58476d1ce4e5b9;
    x ^= x >>> 27;
    x *= 0x94d049bb133111eb;
    x ^= x >>> 31;
    return x;
  }

  // ---- Move generation ------------------------------------------------------

  /// Append all pseudo-legal moves for the side to move to [out].
  void generatePseudoLegal(List<int> out) {
    final us = turn, them = turn ^ 1;
    final ownOcc = occ[us];
    final enemyOcc = occ[them];
    final empty = ~occAll;

    _genPawnMoves(out, us, them, enemyOcc, empty);

    // Knights.
    var bb = pieces[us][knight];
    while (bb != 0) {
      final from = lsb(bb);
      bb &= bb - 1;
      _genFromTargets(out, from, knightAttacks[from] & ~ownOcc, enemyOcc);
    }
    // King (non-castling).
    final kSq = lsb(pieces[us][king]);
    _genFromTargets(out, kSq, kingAttacks[kSq] & ~ownOcc, enemyOcc);
    // Bishops.
    bb = pieces[us][bishop];
    while (bb != 0) {
      final from = lsb(bb);
      bb &= bb - 1;
      _genFromTargets(out, from, bishopAttacks(from, occAll) & ~ownOcc, enemyOcc);
    }
    // Rooks.
    bb = pieces[us][rook];
    while (bb != 0) {
      final from = lsb(bb);
      bb &= bb - 1;
      _genFromTargets(out, from, rookAttacks(from, occAll) & ~ownOcc, enemyOcc);
    }
    // Queens.
    bb = pieces[us][queen];
    while (bb != 0) {
      final from = lsb(bb);
      bb &= bb - 1;
      _genFromTargets(out, from, queenAttacks(from, occAll) & ~ownOcc, enemyOcc);
    }
    _genCastles(out, us, them);
  }

  /// Append pseudo-legal captures (and all promotions) — the quiescence set.
  void generateCaptures(List<int> out) {
    final us = turn, them = turn ^ 1;
    final enemyOcc = occ[them];

    // Pawns: capturing promotions + capturing pushes + en passant, and quiet
    // promotions (a promotion is a big material swing worth resolving).
    final promoRank = us == white ? 7 : 0;
    final fwd = us == white ? 8 : -8;
    final empty = ~occAll;
    var pbb = pieces[us][pawn];
    while (pbb != 0) {
      final from = lsb(pbb);
      pbb &= pbb - 1;
      // Quiet promotion push.
      final one = from + fwd;
      if (one >= 0 && one < 64 && (empty & (1 << one)) != 0 &&
          (one >> 3) == promoRank) {
        _addPromotions(out, from, one, false);
      }
      var caps = pawnAttacks[us][from] & enemyOcc;
      while (caps != 0) {
        final to = lsb(caps);
        caps &= caps - 1;
        if ((to >> 3) == promoRank) {
          _addPromotions(out, from, to, true);
        } else {
          out.add(encodeMove(from, to, flagCapture));
        }
      }
      if (epSquare >= 0 && (pawnAttacks[us][from] & (1 << epSquare)) != 0) {
        out.add(encodeMove(from, epSquare, flagEpCapture));
      }
    }

    void emit(int bb, int Function(int) attacks) {
      while (bb != 0) {
        final from = lsb(bb);
        bb &= bb - 1;
        var t = attacks(from) & enemyOcc;
        while (t != 0) {
          final to = lsb(t);
          t &= t - 1;
          out.add(encodeMove(from, to, flagCapture));
        }
      }
    }

    emit(pieces[us][knight], (f) => knightAttacks[f]);
    emit(pieces[us][king], (f) => kingAttacks[f]);
    emit(pieces[us][bishop], (f) => bishopAttacks(f, occAll));
    emit(pieces[us][rook], (f) => rookAttacks(f, occAll));
    emit(pieces[us][queen], (f) => queenAttacks(f, occAll));
  }

  void _genFromTargets(List<int> out, int from, int targets, int enemyOcc) {
    while (targets != 0) {
      final to = lsb(targets);
      targets &= targets - 1;
      final capture = (enemyOcc & (1 << to)) != 0;
      out.add(encodeMove(from, to, capture ? flagCapture : flagQuiet));
    }
  }

  void _genPawnMoves(
      List<int> out, int us, int them, int enemyOcc, int empty) {
    final fwd = us == white ? 8 : -8;
    final startRank = us == white ? 1 : 6;
    final promoRank = us == white ? 7 : 0;

    var bb = pieces[us][pawn];
    while (bb != 0) {
      final from = lsb(bb);
      bb &= bb - 1;
      final fromRank = from >> 3;

      // Single push.
      final one = from + fwd;
      if (one >= 0 && one < 64 && (empty & (1 << one)) != 0) {
        if ((one >> 3) == promoRank) {
          _addPromotions(out, from, one, false);
        } else {
          out.add(encodeMove(from, one, flagQuiet));
          // Double push.
          final two = from + 2 * fwd;
          if (fromRank == startRank && (empty & (1 << two)) != 0) {
            out.add(encodeMove(from, two, flagDoublePush));
          }
        }
      }

      // Captures.
      var caps = pawnAttacks[us][from] & enemyOcc;
      while (caps != 0) {
        final to = lsb(caps);
        caps &= caps - 1;
        if ((to >> 3) == promoRank) {
          _addPromotions(out, from, to, true);
        } else {
          out.add(encodeMove(from, to, flagCapture));
        }
      }

      // En passant.
      if (epSquare >= 0 && (pawnAttacks[us][from] & (1 << epSquare)) != 0) {
        out.add(encodeMove(from, epSquare, flagEpCapture));
      }
    }
  }

  void _addPromotions(List<int> out, int from, int to, bool capture) {
    final base = capture ? flagPromoCaptureKnight : flagPromoKnight;
    // knight, bishop, rook, queen
    for (var i = 0; i < 4; i++) {
      out.add(encodeMove(from, to, base + i));
    }
  }

  void _genCastles(List<int> out, int us, int them) {
    if (us == white) {
      if ((castling & castleWK) != 0 &&
          (occAll & ((1 << _f1) | (1 << _g1))) == 0 &&
          !isSquareAttacked(_e1, them) &&
          !isSquareAttacked(_f1, them) &&
          !isSquareAttacked(_g1, them)) {
        out.add(encodeMove(_e1, _g1, flagKingCastle));
      }
      if ((castling & castleWQ) != 0 &&
          (occAll & ((1 << _b1) | (1 << _c1) | (1 << _d1))) == 0 &&
          !isSquareAttacked(_e1, them) &&
          !isSquareAttacked(_d1, them) &&
          !isSquareAttacked(_c1, them)) {
        out.add(encodeMove(_e1, _c1, flagQueenCastle));
      }
    } else {
      if ((castling & castleBK) != 0 &&
          (occAll & ((1 << _f8) | (1 << _g8))) == 0 &&
          !isSquareAttacked(_e8, them) &&
          !isSquareAttacked(_f8, them) &&
          !isSquareAttacked(_g8, them)) {
        out.add(encodeMove(_e8, _g8, flagKingCastle));
      }
      if ((castling & castleBQ) != 0 &&
          (occAll & ((1 << _b8) | (1 << _c8) | (1 << _d8))) == 0 &&
          !isSquareAttacked(_e8, them) &&
          !isSquareAttacked(_d8, them) &&
          !isSquareAttacked(_c8, them)) {
        out.add(encodeMove(_e8, _c8, flagQueenCastle));
      }
    }
  }

  static const int _b1 = 1, _b8 = 57;

  /// Legal moves: pseudo-legal filtered by making each and rejecting those that
  /// leave our king in check.
  List<int> generateLegal() {
    final pseudo = <int>[];
    generatePseudoLegal(pseudo);
    final legal = <int>[];
    for (final m in pseudo) {
      makeMove(m);
      // After makeMove, turn flipped; our king is the side that just moved.
      if (!isSquareAttacked(_kingSquareOf(turn ^ 1), turn)) {
        legal.add(m);
      }
      unmakeMove();
    }
    return legal;
  }

  // ---- Make / unmake --------------------------------------------------------

  void makeMove(int m) {
    final from = moveFrom(m), to = moveTo(m), flag = moveFlag(m);
    final us = turn, them = turn ^ 1;
    final movingType = mailbox[from];

    var capturedType = -1;
    if (flag == flagEpCapture) {
      capturedType = pawn;
    } else if (mailbox[to] != -1) {
      capturedType = mailbox[to];
    }

    _undo.add(_Undo(m, capturedType, castling, epSquare, halfmove));

    // Remove captured piece (normal capture handled by moving onto it).
    if (flag == flagEpCapture) {
      final capSq = us == white ? to - 8 : to + 8;
      _removePiece(them, pawn, capSq);
    } else if (capturedType != -1) {
      _removePiece(them, capturedType, to);
    }

    // Move the piece.
    _removePiece(us, movingType, from);
    if (moveIsPromotion(m)) {
      _addPiece(us, movePromoType(m), to);
    } else {
      _addPiece(us, movingType, to);
    }

    // Castling: move the rook.
    if (flag == flagKingCastle) {
      if (us == white) {
        _removePiece(us, rook, _h1);
        _addPiece(us, rook, _f1);
      } else {
        _removePiece(us, rook, _h8);
        _addPiece(us, rook, _f8);
      }
    } else if (flag == flagQueenCastle) {
      if (us == white) {
        _removePiece(us, rook, _a1);
        _addPiece(us, rook, _d1);
      } else {
        _removePiece(us, rook, _a8);
        _addPiece(us, rook, _d8);
      }
    }

    // En-passant target: only after a double push.
    epSquare = flag == flagDoublePush ? (from + to) ~/ 2 : -1;

    // Castling rights.
    castling &= _castleClear[from] & _castleClear[to];

    // Clocks.
    if (movingType == pawn || capturedType != -1) {
      halfmove = 0;
    } else {
      halfmove++;
    }
    if (us == black) fullmove++;

    turn = them;
  }

  void unmakeMove() {
    final u = _undo.removeLast();
    final m = u.move;
    final from = moveFrom(m), to = moveTo(m), flag = moveFlag(m);
    final us = turn ^ 1; // side that had moved
    final them = turn;

    turn = us;
    castling = u.castling;
    epSquare = u.epSquare;
    halfmove = u.halfmove;
    if (us == black) fullmove--;

    // Undo rook move for castling.
    if (flag == flagKingCastle) {
      if (us == white) {
        _removePiece(us, rook, _f1);
        _addPiece(us, rook, _h1);
      } else {
        _removePiece(us, rook, _f8);
        _addPiece(us, rook, _h8);
      }
    } else if (flag == flagQueenCastle) {
      if (us == white) {
        _removePiece(us, rook, _d1);
        _addPiece(us, rook, _a1);
      } else {
        _removePiece(us, rook, _d8);
        _addPiece(us, rook, _a8);
      }
    }

    // Move piece back (undo promotion). Capture the moving piece's type from
    // `to` before removing it — _removePiece clears mailbox[to].
    if (moveIsPromotion(m)) {
      _removePiece(us, movePromoType(m), to);
      _addPiece(us, pawn, from);
    } else {
      final movedType = mailbox[to];
      _removePiece(us, movedType, to);
      _addPiece(us, movedType, from);
    }

    // Restore captured piece.
    if (flag == flagEpCapture) {
      final capSq = us == white ? to - 8 : to + 8;
      _addPiece(them, pawn, capSq);
    } else if (u.capturedType != -1) {
      _addPiece(them, u.capturedType, to);
    }
  }

  /// Pass the turn to the opponent without moving (null-move pruning). Only the
  /// side to move and en-passant square change; the board is untouched. Never
  /// call when [inCheck] (the null side could be mated).
  void makeNullMove() {
    _undo.add(_Undo(-1, -1, castling, epSquare, halfmove));
    epSquare = -1;
    halfmove++;
    turn ^= 1;
  }

  void unmakeNullMove() {
    final u = _undo.removeLast();
    turn ^= 1;
    epSquare = u.epSquare;
    halfmove = u.halfmove;
  }

  void _removePiece(int color, int type, int sq) {
    final b = 1 << sq;
    pieces[color][type] ^= b;
    occ[color] ^= b;
    occAll ^= b;
    mailbox[sq] = -1;
  }

  // ---- FEN ------------------------------------------------------------------

  String toFen() {
    final sb = StringBuffer();
    for (var rank = 7; rank >= 0; rank--) {
      var empty = 0;
      for (var file = 0; file < 8; file++) {
        final sq = rank * 8 + file;
        final type = mailbox[sq];
        if (type == -1) {
          empty++;
        } else {
          if (empty > 0) {
            sb.write(empty);
            empty = 0;
          }
          final isWhite = (occ[white] & (1 << sq)) != 0;
          final ch = _pieceChar(type);
          sb.write(isWhite ? ch.toUpperCase() : ch);
        }
      }
      if (empty > 0) sb.write(empty);
      if (rank > 0) sb.write('/');
    }
    sb.write(turn == white ? ' w ' : ' b ');
    final c = StringBuffer();
    if ((castling & castleWK) != 0) c.write('K');
    if ((castling & castleWQ) != 0) c.write('Q');
    if ((castling & castleBK) != 0) c.write('k');
    if ((castling & castleBQ) != 0) c.write('q');
    sb.write(c.isEmpty ? '-' : c.toString());
    sb.write(' ');
    sb.write(epSquare >= 0 ? _squareName(epSquare) : '-');
    sb.write(' $halfmove $fullmove');
    return sb.toString();
  }

  /// Long-algebraic (UCI) string for [m], e.g. `e2e4`, `e7e8q`.
  String moveToUci(int m) {
    final s = '${_squareName(moveFrom(m))}${_squareName(moveTo(m))}';
    if (moveIsPromotion(m)) return '$s${_pieceChar(movePromoType(m))}';
    return s;
  }

  /// Find the legal move matching UCI string [uci], or -1.
  int moveFromUci(String uci) {
    for (final m in generateLegal()) {
      if (moveToUci(m) == uci) return m;
    }
    return -1;
  }
}

int _pieceTypeFromChar(String c) {
  switch (c) {
    case 'p':
      return pawn;
    case 'n':
      return knight;
    case 'b':
      return bishop;
    case 'r':
      return rook;
    case 'q':
      return queen;
    case 'k':
      return king;
  }
  throw ArgumentError('bad piece char: $c');
}

String _pieceChar(int type) => const ['p', 'n', 'b', 'r', 'q', 'k'][type];

int _squareFromName(String s) {
  final file = s.codeUnitAt(0) - 0x61; // 'a'
  final rank = s.codeUnitAt(1) - 0x31; // '1'
  return rank * 8 + file;
}

String _squareName(int sq) {
  final file = String.fromCharCode(0x61 + (sq & 7));
  final rank = String.fromCharCode(0x31 + (sq >> 3));
  return '$file$rank';
}

/// Count leaf nodes at [depth] — the standard move-generator correctness test.
int perft(Position p, int depth) {
  if (depth == 0) return 1;
  final moves = <int>[];
  p.generatePseudoLegal(moves);
  var nodes = 0;
  for (final m in moves) {
    p.makeMove(m);
    if (!p.isSquareAttacked(p._kingSquareOf(p.turn ^ 1), p.turn)) {
      nodes += depth == 1 ? 1 : perft(p, depth - 1);
    }
    p.unmakeMove();
  }
  return nodes;
}
