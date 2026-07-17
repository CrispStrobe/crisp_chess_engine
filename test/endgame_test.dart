// Endgame mop-up: material+PST alone gives no gradient in a bare-king ending,
// so a shallow search just shuffles and never converts. The mop-up term drives
// the lone king to a corner and brings the strong king in. These positions are
// *not* convertible by the material+PST baseline at these depths (it shuffles
// to the 160-ply cap), so a finite mate here is the improvement.
import 'package:crisp_chess_engine/bitboard.dart';
import 'package:test/test.dart';

/// Plays [fen] out with the engine on both sides at [depth]; returns the ply on
/// which mate was delivered, or -1 if it failed to convert (stalemate, the
/// 50-move rule, or the ply cap).
int _pliesToMate(String fen, int depth) {
  final p = Position.fromFen(fen);
  for (var ply = 0; ply < 160; ply++) {
    if (p.generateLegal().isEmpty) return p.inCheck ? ply : -1; // mate : stalemate
    if (p.halfmove >= 100) return -1; // 50-move rule: failed to convert
    final r = BitboardSearch(p).search(depth);
    if (r == null) return -1;
    p.makeMove(p.moveFromUci(r.bestMove));
  }
  return -1; // shuffled to the cap
}

void main() {
  test('K+Q vs K is mated at shallow depth', () {
    final plies = _pliesToMate('4k3/8/8/8/8/8/8/3QK3 w - - 0 1', 6);
    expect(plies, greaterThan(0));
    expect(plies, lessThanOrEqualTo(50));
  });

  test('K+R vs K is mated', () {
    for (final fen in const [
      '4k3/8/8/8/8/8/8/R3K3 w - - 0 1',
      '7k/8/8/8/8/8/8/R2K4 w - - 0 1',
    ]) {
      final plies = _pliesToMate(fen, 8);
      expect(plies, greaterThan(0), reason: 'did not convert: $fen');
      expect(plies, lessThanOrEqualTo(80));
    }
  });

  test('mop-up does not fire when both sides have material', () {
    // Both sides have a rook — neither king is bare, so the mop-up must not
    // distort the evaluation: a materially symmetric position stays ~0.
    final p = Position.fromFen('r3k3/8/8/8/8/8/8/R3K3 w - - 0 1');
    expect(evaluatePosition(p).abs(), lessThan(30));
  });

  test('a bare king with no mating material gets no mop-up drive', () {
    // K+B vs K is a draw; the mop-up deliberately does not apply (no rook or
    // queen), so the term contributes nothing beyond material+PST.
    final p = Position.fromFen('4k3/8/8/8/8/8/8/2B1K3 w - - 0 1');
    expect(evaluatePosition(p), evaluateMaterialPst(p));
  });
}
