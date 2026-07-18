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

  // A malformed en-passant token used to leak a RangeError out of
  // `codeUnitAt(1)` (a 1-char field like "e") or an out-of-range square name
  // ("z9"). It must now reject with a plain ArgumentError — and crucially NOT a
  // RangeError (which, being an ArgumentError subtype, would slip past an
  // ArgumentError allow-list). GUARD:epsquare.
  final cleanReject = throwsA(
      isA<ArgumentError>().having((e) => e is RangeError, 'is RangeError', isFalse));

  group('fromFen rejects a malformed en-passant field cleanly', () {
    test('1-char ep token', () {
      expect(() => Position.fromFen('8/8/8/8/8/8/8/8 w - e 0 1'), cleanReject);
    });

    test('ep token out of the a1..h8 range', () {
      expect(() => Position.fromFen('8/8/8/8/8/8/8/8 w - z9 0 1'), cleanReject);
    });

    test('minimized fuzz reproducer', () {
      expect(() => Position.fromFen('8 - 0 1'), cleanReject);
    });
  });

  group('valid positions still parse', () {
    for (final fen in const [
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', // startpos
      '8/8/8/8/4k3/8/4K3/8 w - - 0 1', // kings only
      'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1', // castling rights
      '8/8/8/8/8/8/8/8 w - - 0 1', // empty board
      'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2', // ep sq
    ]) {
      test('parses "$fen"', () {
        expect(() => Position.fromFen(fen), returnsNormally);
      });
    }
  });
}
