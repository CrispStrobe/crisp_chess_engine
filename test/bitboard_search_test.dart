import 'package:crisp_chess_engine/bitboard.dart';
import 'package:test/test.dart';

const _startpos = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

Set<String> _legal(Position p) => p.generateLegal().map(p.moveToUci).toSet();

SearchResult _search(String fen, int depth) =>
    BitboardSearch(Position.fromFen(fen)).search(depth)!;

void main() {
  group('tactics (known best move)', () {
    test('mate in 1 — back rank Ra8#', () {
      final r = _search('6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1', 4);
      expect(r.bestMove, 'a1a8');
      expect(r.score, greaterThan(900000));
    });

    test('finds a forced mate (two-rook ladder)', () {
      final r = _search('7k/R7/1R6/8/8/8/8/6K1 w - - 0 1', 5);
      expect(r.score, greaterThan(900000), reason: 'should see a forced mate');
      expect(r.bestMove, 'b6b8'); // Rb8# (Ra7 covers the 7th rank)
    });

    test('wins a hanging queen', () {
      final r = _search('4k3/8/8/3q4/4P3/8/8/4K3 w - - 0 1', 4);
      expect(r.bestMove, 'e4d5');
    });

    test('values a queen promotion as winning', () {
      // Both a7a8q and (dawdling) king moves keep the queen, so a plain
      // material+PST search ties them — assert the winning score rather than a
      // specific tie-broken move. Promotion *generation* is covered by perft.
      final r = _search('8/P6k/8/8/8/8/7K/8 w - - 0 1', 4);
      expect(r.score, greaterThan(850));
    });

    test('finds en-passant capture when it is best', () {
      // White b5 pawn, black just played c7-c5; bxc6 e.p. wins the pawn.
      final r = _search('4k3/8/8/1Pp5/8/8/8/4K3 w - c6 0 1', 3);
      expect(r.bestMove, 'b5c6');
    });
  });

  group('robustness', () {
    test('always returns a legal move across depths', () {
      for (final fen in [
        _startpos,
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
        '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
        'r2q1rk1/pp1nbppp/2p1pn2/3p4/2PP4/2NBPN2/PP3PPP/R1BQ1RK1 w - - 4 9',
      ]) {
        final p = Position.fromFen(fen);
        final legal = _legal(p);
        for (var d = 1; d <= 5; d++) {
          final r = BitboardSearch(Position.fromFen(fen)).search(d)!;
          expect(legal, contains(r.bestMove),
              reason: 'illegal move at depth $d in $fen: ${r.bestMove}');
        }
      }
    });

    test('search leaves the position untouched', () {
      final p = Position.fromFen(
          'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1');
      final before = p.toFen();
      BitboardSearch(p).search(6);
      expect(p.toFen(), before);
    });

    test('deterministic — same position gives same move', () {
      final a = _search(_startpos, 6);
      final b = _search(_startpos, 6);
      expect(a.bestMove, b.bestMove);
      expect(a.score, b.score);
    });
  });

  group('time budget', () {
    test('bounds latency (depth 64 would never finish)', () {
      final sw = Stopwatch()..start();
      final r = BitboardSearch(Position.fromFen(
              'r2q1rk1/pp1nbppp/2p1pn2/3p4/2PP4/2NBPN2/PP3PPP/R1BQ1RK1 w - - 4 9'))
          .search(64, timeBudget: const Duration(milliseconds: 500));
      sw.stop();
      expect(r, isNotNull);
      expect(sw.elapsedMilliseconds, lessThan(2000));
      expect(_legal(Position.fromFen(
              'r2q1rk1/pp1nbppp/2p1pn2/3p4/2PP4/2NBPN2/PP3PPP/R1BQ1RK1 w - - 4 9')),
          contains(r!.bestMove));
    });
  });
}
