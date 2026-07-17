// Self-play A/B harness (run explicitly): dart run test/selfplay.dart
//
// Plays deterministic fixed-depth games between two evaluators from a set of
// varied openings, each opening played both colors. Reports the score of eval A
// (new/extended) vs eval B (material+PST baseline). >50% means A is stronger.
import 'package:crisp_chess_engine/bitboard.dart';

// Time budget per move — the real-play condition (accounts for eval cost, not
// just per-node strength). Set _budgetMs = 0 to use fixed _depth instead.
const int _budgetMs = 0;
const int _depth = 6;
const int _maxPlies = 160;

const List<String> _openings = [
  'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3', // open
  'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2', // Sicilian
  'rnbqkbnr/pppp1ppp/4p3/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2', // French
  'rnbqkbnr/pp1ppppp/2p5/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2', // Caro-Kann
  'rnbqkb1r/pppp1ppp/4pn2/8/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 3', // QGD/Indian
  'rnbqkbnr/ppp1pppp/8/3p4/2PP4/8/PP2PPPP/RNBQKBNR b KQkq c3 0 2', // QG
  'rnbqkbnr/ppp1pppp/8/3p4/8/5N2/PPPPPPPP/RNBQKB1R w KQkq - 0 2', // Reti
  'rnbqkbnr/pppppppp/8/8/2P5/8/PP1PPPPP/RNBQKBNR b KQkq c3 0 1', // English
  'r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3', // Ruy
  'rnbqkbnr/pppp1ppp/8/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR b KQkq - 1 2', // Italian
  'rnbqkb1r/ppp2ppp/4pn2/3p4/2PP4/2N5/PP2PPPP/R1BQKBNR w KQkq - 2 4', // QGD
  'rnbqkb1r/1p2pppp/p2p1n2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w KQkq - 0 6', // Najdorf
  'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4', // Italian2
  'rnbqk2r/ppppppbp/5np1/8/2PP4/2N5/PP2PPPP/R1BQKBNR w KQkq - 2 4', // KID
  'rn1qkbnr/pp2pppp/2p5/3p1b2/2PP4/5N2/PP2PPPP/RNBQKB1R w KQkq - 2 4', // Slav
  'r1bqkbnr/pp1ppppp/2n5/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3', // Sicilian2
  'rnbqkbnr/pp2pppp/2p5/3p4/3P4/2N5/PPP1PPPP/R1BQKBNR w KQkq - 0 3', // Caro2
  'rnbqkb1r/pppppp1p/5np1/8/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 0 3', // KID2
];

int _rawMaterialWhitePov(Position p) {
  var s = 0;
  for (var t = pawn; t <= queen; t++) {
    s += (popcount(p.pieces[white][t]) - popcount(p.pieces[black][t])) *
        pieceValue[t];
  }
  return s;
}

bool _insufficient(Position p) {
  if ((p.pieces[white][pawn] | p.pieces[black][pawn]) != 0) return false;
  if ((p.pieces[white][rook] |
          p.pieces[black][rook] |
          p.pieces[white][queen] |
          p.pieces[black][queen]) !=
      0) {
    return false;
  }
  final wMinors =
      popcount(p.pieces[white][knight]) + popcount(p.pieces[white][bishop]);
  final bMinors =
      popcount(p.pieces[black][knight]) + popcount(p.pieces[black][bishop]);
  return wMinors <= 1 && bMinors <= 1; // K(+minor) vs K(+minor)
}

/// Returns White's result: 1.0 win, 0.5 draw, 0.0 loss.
double _playGame(
    String fen, int Function(Position) whiteEval, int Function(Position) blackEval) {
  final pos = Position.fromFen(fen);
  final seen = <int, int>{};
  for (var ply = 0; ply < _maxPlies; ply++) {
    if (pos.generateLegal().isEmpty) {
      return pos.inCheck ? (pos.turn == white ? 0.0 : 1.0) : 0.5;
    }
    if (pos.halfmove >= 100 || _insufficient(pos)) return 0.5;
    final h = pos.hash();
    seen[h] = (seen[h] ?? 0) + 1;
    if (seen[h]! >= 3) return 0.5;

    final eval = pos.turn == white ? whiteEval : blackEval;
    final r = BitboardSearch(pos, evaluator: eval).search(
      _budgetMs > 0 ? 64 : _depth,
      timeBudget:
          _budgetMs > 0 ? Duration(milliseconds: _budgetMs) : null,
    );
    if (r == null) return 0.5;
    pos.makeMove(pos.moveFromUci(r.bestMove));
  }
  final mat = _rawMaterialWhitePov(pos); // adjudicate by raw material
  if (mat > 500) {
    return 1.0;
  }
  if (mat < -500) {
    return 0.0;
  }
  return 0.5;
}

void main() {
  final a = evaluatePosition; // shipping eval
  final b = evaluateMaterialPst; // baseline
  var aScore = 0.0;
  var games = 0;
  var w = 0, d = 0, l = 0;

  for (final fen in _openings) {
    // A as White.
    final r1 = _playGame(fen, a, b);
    aScore += r1;
    if (r1 == 1.0) {
      w++;
    } else if (r1 == 0.5) {
      d++;
    } else {
      l++;
    }
    games++;
    // A as Black (A's score = 1 - White's result).
    final r2 = 1 - _playGame(fen, b, a);
    aScore += r2;
    if (r2 == 1.0) {
      w++;
    } else if (r2 == 0.5) {
      d++;
    } else {
      l++;
    }
    games++;
    print('${fen.split(' ')[0].padRight(45)}  A-white=$r1  A-black=$r2');
  }

  final pct = (aScore / games * 100).toStringAsFixed(1);
  print('');
  print('extended eval (A) vs material+PST (B): '
      '$aScore / $games = $pct%   (W$w D$d L$l for A)');
}
