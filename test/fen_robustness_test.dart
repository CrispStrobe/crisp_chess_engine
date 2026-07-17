// Position.fromFen must reject a malformed board layout with a descriptive
// ArgumentError (as it already does for a bad piece char) — not leak a cryptic
// RangeError out of the mailbox when a rank holds too many pieces or the string
// has too many ranks (both push the square outside 0..63).
import 'package:crisp_chess_engine/bitboard.dart';
import 'package:test/test.dart';

void main() {
  // The clean rejection carries a descriptive message; RangeError (a subtype of
  // ArgumentError) would satisfy throwsArgumentError, so assert the message to
  // prove the bounds guard — not the raw mailbox overrun — is what fired.
  final outOfBounds = throwsA(isA<ArgumentError>()
      .having((e) => '${e.message}', 'message', contains('out of bounds')));

  group('fromFen rejects malformed placement cleanly', () {
    test('too many pieces in a rank (file overflow)', () {
      expect(() => Position.fromFen('pppppppppppppppp/8/8/8/8/8/8/8 w - - 0 1'),
          outOfBounds);
    });

    test('too many ranks (rank underflow)', () {
      expect(() => Position.fromFen('p/p/p/p/p/p/p/p/p/p/p/p w - - 0 1'),
          outOfBounds);
    });

    test('a long unbroken run of pieces', () {
      expect(() => Position.fromFen('${'P' * 40} w - - 0 1'), outOfBounds);
    });

    test('a bad piece char still rejects', () {
      expect(() => Position.fromFen('xyz w - - 0 1'), throwsArgumentError);
    });
  });

  group('valid positions still parse', () {
    for (final fen in const [
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', // startpos
      '8/8/8/8/4k3/8/4K3/8 w - - 0 1', // kings only
      'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1', // castling rights
      '8/8/8/8/8/8/8/8 w - - 0 1', // empty board
    ]) {
      test('parses "$fen"', () {
        expect(() => Position.fromFen(fen), returnsNormally);
      });
    }
  });
}
