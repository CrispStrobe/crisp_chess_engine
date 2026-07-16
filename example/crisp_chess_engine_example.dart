// Finds the best move in a few positions with the pure-Dart engine.
// Run with: dart run example/crisp_chess_engine_example.dart
import 'package:crisp_chess_engine/crisp_chess_engine.dart';

void main() {
  // A back-rank mate in one — the engine should play Ra8#.
  final mate = searchPosition('6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1', depth: 4);
  print('mate-in-1 best move: ${mate?.bestMove}  (score ${mate?.score})');

  // The opening position — any sound first move, searched to depth 5.
  final opening = searchPosition(
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    depth: 5,
  );
  print('opening best move:   ${opening?.bestMove}  '
      '(${opening?.nodesSearched} nodes, depth ${opening?.depth})');
}
