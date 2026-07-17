import 'package:crisp_chess_engine/bitboard.dart';
import 'package:test/test.dart';

// The extra terms in [evaluatePosition] over [evaluateMaterialPst], from the
// side-to-move's point of view.
int _extended(String fen) {
  final p = Position.fromFen(fen);
  return evaluatePosition(p) - evaluateMaterialPst(p);
}

void main() {
  test('start position is balanced (both evaluators)', () {
    final p = Position.startpos();
    expect(evaluateMaterialPst(p), 0);
    expect(evaluatePosition(p), 0);
  });

  test('evaluation is colour-symmetric', () {
    // A position and its vertical mirror with the other side to move must score
    // the same from each mover's perspective.
    final a = evaluatePosition(Position.fromFen(
        'r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 0 1'));
    final b = evaluatePosition(Position.fromFen(
        'rnbqk2r/ppp2ppp/3p1n2/2b1p3/2B1P3/2N2N2/PPPP1PPP/R1BQK2R b KQkq - 0 1'));
    expect(a, b);
  });

  test('bishop pair is worth a bonus', () {
    // White has two bishops, no pawns — the only extra term is the pair bonus.
    expect(_extended('4k3/8/8/8/8/8/8/2B1KB2 w - - 0 1'), 30);
  });

  test('a more advanced passed pawn scores higher', () {
    final e5 = evaluatePosition(
        Position.fromFen('4k3/8/8/4P3/8/8/8/4K3 w - - 0 1'));
    final e2 = evaluatePosition(
        Position.fromFen('4k3/8/8/8/8/8/4P3/4K3 w - - 0 1'));
    expect(e5, greaterThan(e2));
  });

  test('doubled + isolated pawns are penalised', () {
    // White c2+c3 (doubled, isolated) — the extended term must be net negative.
    expect(_extended('4k3/8/8/8/8/2P5/2P5/4K3 w - - 0 1'), lessThan(0));
  });
}
