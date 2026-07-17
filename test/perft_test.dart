// Perft: the standard move-generator correctness test. Leaf-node counts are
// compared against long-published reference values. If make/unmake, castling,
// en passant, promotions or legality filtering are wrong, these diverge.
import 'package:crisp_chess_engine/bitboard.dart';
import 'package:test/test.dart';

void main() {
  group('perft — standard positions', () {
    test('startpos', () {
      final p = Position.startpos();
      expect(perft(p, 1), 20);
      expect(perft(p, 2), 400);
      expect(perft(p, 3), 8902);
      expect(perft(p, 4), 197281);
      expect(perft(p, 5), 4865609);
    });

    test('Kiwipete', () {
      final p = Position.fromFen(
          'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1');
      expect(perft(p, 1), 48);
      expect(perft(p, 2), 2039);
      expect(perft(p, 3), 97862);
      expect(perft(p, 4), 4085603);
    });

    test('position 3 (endgame, ep-heavy)', () {
      final p = Position.fromFen('8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1');
      expect(perft(p, 1), 14);
      expect(perft(p, 2), 191);
      expect(perft(p, 3), 2812);
      expect(perft(p, 4), 43238);
      expect(perft(p, 5), 674624);
    });

    test('position 4 (promotions, pins)', () {
      final p = Position.fromFen(
          'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1');
      expect(perft(p, 1), 6);
      expect(perft(p, 2), 264);
      expect(perft(p, 3), 9467);
      expect(perft(p, 4), 422333);
    });

    test('position 5', () {
      final p = Position.fromFen(
          'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8');
      expect(perft(p, 1), 44);
      expect(perft(p, 2), 1486);
      expect(perft(p, 3), 62379);
    });

    test('position 6', () {
      final p = Position.fromFen(
          'r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10');
      expect(perft(p, 1), 46);
      expect(perft(p, 2), 2079);
      expect(perft(p, 3), 89890);
    });
  });

  test('make/unmake restores the position exactly (via FEN round trip)', () {
    final p = Position.fromFen(
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1');
    final before = p.toFen();
    final moves = p.generateLegal();
    for (final m in moves) {
      p.makeMove(m);
      p.unmakeMove();
      expect(p.toFen(), before, reason: 'broken by ${p.moveToUci(m)}');
    }
  });
}
