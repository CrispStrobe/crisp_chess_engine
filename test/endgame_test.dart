// Endgame mop-up: material+PST alone gives no gradient in a bare-king ending,
// so a shallow search just shuffles and never converts. The mop-up term drives
// the lone king to a corner and brings the strong king in. These positions are
// *not* convertible by the material+PST baseline at these depths (it shuffles
// to the 160-ply cap), so a finite mate here is the improvement.
import 'package:crisp_chess_engine/bitboard.dart';
import 'package:test/test.dart';

/// Plays [fen] out with the engine on both sides at [depth]; returns the ply on
/// which mate was delivered, or -1 if it failed to convert (stalemate, the
/// 50-move rule, or the ply cap). When [seedHistory] is set, each search is
/// given the game's position history so it avoids repeating (shuffling).
int _pliesToMate(String fen, int depth, {bool seedHistory = false}) {
  final p = Position.fromFen(fen);
  final history = <int>[p.hash()];
  for (var ply = 0; ply < 160; ply++) {
    if (p.generateLegal().isEmpty) return p.inCheck ? ply : -1; // mate : stalemate
    if (p.halfmove >= 100) return -1; // 50-move rule: failed to convert
    final r = BitboardSearch(p,
            repetitionHistory: seedHistory ? List.of(history) : null)
        .search(depth);
    if (r == null) return -1;
    p.makeMove(p.moveFromUci(r.bestMove));
    history.add(p.hash());
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

  test('game history lets a shallow search convert K+R vs K', () {
    // At depth 6 the rook mate is beyond the horizon, so without history the
    // engine shuffles (repeats) forever. Seeding the game history makes a
    // repetition score as a draw, forcing progress — so it converts.
    for (final fen in const [
      '4k3/8/8/8/8/8/8/R3K3 w - - 0 1',
      '7k/8/8/8/8/8/8/R2K4 w - - 0 1',
      '8/8/8/4k3/8/8/8/R3K3 w - - 0 1', // central king — hardest
    ]) {
      expect(_pliesToMate(fen, 6, seedHistory: false), -1,
          reason: 'baseline should shuffle at depth 6: $fen');
      final withHistory = _pliesToMate(fen, 6, seedHistory: true);
      expect(withHistory, greaterThan(0),
          reason: 'history should let it convert: $fen');
      expect(withHistory, lessThanOrEqualTo(90));
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
