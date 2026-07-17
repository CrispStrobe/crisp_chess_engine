// The chess-package AlphaBetaSearch (the web path) now has the same endgame
// behaviour as the bitboard engine: a mop-up gradient plus game-history
// repetition awareness, so it converts won bare-king endings instead of
// shuffling to the 50-move rule.
import 'package:chess/chess.dart' as chess;
import 'package:crisp_chess_engine/crisp_chess_engine.dart';
import 'package:test/test.dart';

/// Play [fen] out with AlphaBetaSearch on both sides at [depth]. Returns the ply
/// of mate, or -1 if it failed to convert. Seeds each search with the game's
/// position history when [seedHistory] is set.
int _pliesToMate(String fen, int depth, {bool seedHistory = false}) {
  final game = chess.Chess.fromFEN(fen);
  final history = <int>[AlphaBetaSearch.positionKeyOf(game)];
  for (var ply = 0; ply < 140; ply++) {
    final moves = game.generate_moves();
    if (moves.isEmpty) return game.in_check ? ply : -1;
    if (game.half_moves >= 100) return -1; // 50-move rule
    final r = AlphaBetaSearch(game,
            repetitionHistory: seedHistory ? List.of(history) : null)
        .search(depth);
    if (r == null) return -1;
    final u = r.bestMove;
    game.move({
      'from': u.substring(0, 2),
      'to': u.substring(2, 4),
      'promotion': u.length > 4 ? u.substring(4, 5) : null,
    });
    history.add(AlphaBetaSearch.positionKeyOf(game));
  }
  return -1;
}

void main() {
  test('mop-up bonus applies in a bare-king ending', () {
    // White K+R vs a lone black king: the mop-up should make the score depend
    // on where the black king stands — worse (for Black) in the corner.
    final centre = evaluate(chess.Chess.fromFEN('8/8/8/4k3/8/8/8/R3K3 w - - 0 1'));
    final corner = evaluate(chess.Chess.fromFEN('7k/8/8/8/8/8/8/R3K3 w - - 0 1'));
    expect(corner, greaterThan(centre),
        reason: 'driving the lone king to the corner should score higher');
  });

  test('mop-up does not fire when both sides have material', () {
    final e = evaluate(chess.Chess.fromFEN('r3k3/8/8/8/8/8/8/R3K3 w - - 0 1'));
    expect(e.abs(), lessThan(60)); // symmetric-ish; mop-up must not distort
  });

  test('positionKeyOf is stable and distinguishes positions', () {
    final a = chess.Chess.fromFEN('4k3/8/8/8/8/8/8/R3K3 w - - 0 1');
    final b = chess.Chess.fromFEN('4k3/8/8/8/8/8/8/R3K3 w - - 0 1');
    final c = chess.Chess.fromFEN('4k3/8/8/8/8/8/8/R3K3 b - - 0 1');
    expect(AlphaBetaSearch.positionKeyOf(a), AlphaBetaSearch.positionKeyOf(b));
    expect(AlphaBetaSearch.positionKeyOf(a),
        isNot(AlphaBetaSearch.positionKeyOf(c)));
  });

  test('converts K+R vs K with game history (would otherwise shuffle)', () {
    // This position shuffles without repetition awareness.
    const fen = '7k/8/8/8/8/8/8/R2K4 w - - 0 1';
    expect(_pliesToMate(fen, 6, seedHistory: false), -1,
        reason: 'baseline shuffles at depth 6');
    final withHistory = _pliesToMate(fen, 6, seedHistory: true);
    expect(withHistory, greaterThan(0));
    expect(withHistory, lessThanOrEqualTo(90));
  });
}
