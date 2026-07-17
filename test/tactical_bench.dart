// Strength harness (not a _test.dart — run explicitly):
//   dart run test/tactical_bench.dart
//
// Metric without external "known answers": a deep search (the oracle) defines
// the target move for each position; we then measure how often a short search
// reaches the same conclusion, plus how many forced mates it finds. Search
// improvements should raise both at a fixed short budget.
import 'package:crisp_chess_engine/bitboard.dart';

const _oracleMs = 3000;
const _shortMs = 150;

const _positions = <String>[
  // Sharp middlegames and known tactical shots.
  '2rr3k/pp3pp1/1nnqbN1p/3pN3/2pP4/2P3Q1/PPB4P/R4RK1 w - - 0 1',
  'r3r1k1/pp3ppp/2p5/2bp4/8/2B2Q1P/PPP2PP1/R4RK1 b - - 0 1',
  '5rk1/pp4pp/4p3/2R3Q1/3n4/2q4r/P1P2PPP/5RK1 b - - 0 1',
  'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
  'r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 1',
  '3r2k1/p4p1p/1p2p1p1/2b5/2P5/1P1R1P2/P5PP/4R1K1 w - - 0 1',
  'r2q1rk1/1b1nbppp/p2ppn2/1p6/3NPP2/1BN1B3/PPPQ2PP/R4RK1 w - - 0 1',
  '2r3k1/pp2Bpbp/4b1p1/3p4/3P4/2P2N2/P4PPP/3R2K1 w - - 0 1',
  'r1b2rk1/2q1b1pp/p2ppn2/1p6/3QP3/1BN1B3/PPP3PP/R4RK1 w - - 0 1',
  'r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 0 1',
  // Forced mates.
  '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
  '7k/R7/1R6/8/8/8/8/6K1 w - - 0 1',
  '6k1/8/6K1/8/8/8/8/1Q6 w - - 0 1',
  '4k3/8/4K3/8/8/8/8/R7 w - - 0 1',
  // Endgames / quiet (agreement still meaningful).
  '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
  'r2q1rk1/pp1nbppp/2p1pn2/3p4/2PP4/2NBPN2/PP3PPP/R1BQ1RK1 w - - 4 9',
];

const int _mateThreshold = 900000;

void main() {
  var mateFindable = 0;
  var mateFound = 0;
  var agree = 0;
  var totalDepth = 0;

  for (final fen in _positions) {
    final oracle = BitboardSearch(Position.fromFen(fen))
        .search(64, timeBudget: const Duration(milliseconds: _oracleMs))!;
    final short = BitboardSearch(Position.fromFen(fen))
        .search(64, timeBudget: const Duration(milliseconds: _shortMs))!;

    if (oracle.score.abs() >= _mateThreshold) {
      mateFindable++;
      if (short.score.abs() >= _mateThreshold) mateFound++;
    }
    if (short.bestMove == oracle.bestMove) agree++;
    totalDepth += short.depth;
  }

  // Efficiency: nodes to reach a fixed depth on representative positions.
  const fixedDepth = 8;
  var totalNodes = 0;
  for (final fen in _positions) {
    totalNodes += BitboardSearch(Position.fromFen(fen)).search(fixedDepth)!.nodesSearched;
  }

  print('agreement with 3s oracle at ${_shortMs}ms: $agree / ${_positions.length}');
  print('forced mates found at ${_shortMs}ms:        $mateFound / $mateFindable');
  print('avg depth reached in ${_shortMs}ms:         ${(totalDepth / _positions.length).toStringAsFixed(2)}');
  print('total nodes to depth $fixedDepth (all pos):    $totalNodes');
}
