// Static Exchange Evaluation — the value a capture wins/loses after the full
// sequence of optimal recaptures on the target square. Used to prune losing
// captures in quiescence.
import 'package:crisp_chess_engine/bitboard.dart';
import 'package:test/test.dart';

int _see(String fen, String uci) {
  final p = Position.fromFen(fen);
  return p.see(p.moveFromUci(uci));
}

void main() {
  test('capturing an undefended pawn wins a pawn', () {
    expect(_see('4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1', 'e4d5'), 100);
  });

  test('pawn takes queen defended by a pawn: queen minus pawn', () {
    // Black e6 pawn recaptures on d5.
    expect(_see('4k3/8/4p3/3q4/4P3/8/8/4K3 w - - 0 1', 'e4d5'), 800);
  });

  test('pawn takes an undefended queen: full queen', () {
    expect(_see('4k3/2p5/8/3q4/4P3/8/8/4K3 w - - 0 1', 'e4d5'), 900);
  });

  test('rook takes a pawn defended by a pawn: losing exchange', () {
    expect(_see('4k3/8/2p5/3p4/8/3R4/8/4K3 w - - 0 1', 'd3d5'), -400);
  });

  test('knight takes knight defended by a pawn: even', () {
    expect(_see('4k3/2p5/3n4/8/4N3/8/8/4K3 w - - 0 1', 'e4d6'), 0);
  });

  test('queen takes pawn defended by a knight: loses the queen', () {
    expect(_see('4k3/8/1n6/3p4/8/8/3Q4/4K3 w - - 0 1', 'd2d5'), -800);
  });

  test('a non-capture has zero SEE', () {
    expect(_see('4k3/8/8/8/4P3/8/8/4K3 w - - 0 1', 'e4e5'), 0);
  });
}
