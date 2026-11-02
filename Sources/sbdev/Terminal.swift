import Foundation

/// Whether standard input is a terminal (so `sbdev` can keep running after its input ends when
/// it was started from a script). Windows names these functions with an underscore and warns about
/// the POSIX names.
func standardInputIsTerminal() -> Bool {
    #if os(Windows)
    return _isatty(_fileno(stdin)) != 0
    #else
    return isatty(fileno(stdin)) != 0
    #endif
}
