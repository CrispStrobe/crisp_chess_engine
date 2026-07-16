import 'package:crisp_chess_engine/crisp_chess_engine.dart';
import 'package:test/test.dart';

void main() {
  test('finds a back-rank mate in one (Ra8#)', () {
    final r = searchPosition('6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1', depth: 3);
    expect(r, isNotNull);
    expect(r!.bestMove, 'a1a8');
  });

  test('reports a mate score when a forced mate exists', () {
    // White queen + king box the black king in the corner; several mates in
    // one exist, so assert the (large) mate score rather than a specific move.
    final r = searchPosition('k7/8/1K6/8/8/8/8/1Q6 w - - 0 1', depth: 3);
    expect(r, isNotNull);
    expect(r!.score, greaterThan(90000));
  });

  test('returns a legal move from the opening position', () {
    final r = searchPosition(
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      depth: 3,
    );
    expect(r, isNotNull);
    // UCI: from-square + to-square, e.g. e2e4.
    expect(r!.bestMove, matches(RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$')));
    expect(r.depth, 3);
    expect(r.nodesSearched, greaterThan(0));
  });

  test('captures a hanging queen', () {
    // White to move; a free black queen on d5 is taken by the pawn on e4.
    final r = searchPosition('4k3/8/8/3q4/4P3/8/8/4K3 w - - 0 1', depth: 4);
    expect(r, isNotNull);
    expect(r!.bestMove, 'e4d5');
  });
}
