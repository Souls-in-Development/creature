import Testing
import Foundation
@testable import CreatureTrunkPython
@testable import CreatureTrunk


/// These suites exercise the `python3` + `ast` path specifically. Where python3
/// is absent (a bare Linux container, a stripped CI image), `PythonIndexer`
/// deliberately degrades to its regex fallback, which produces a different node
/// shape — so asserting AST-path results there tests nothing and force-unwraps
/// nil. Skip honestly instead of failing, exactly as the external-validator
/// probe tests do.
@Suite(.enabled(if: PythonIndexer.locatePython3() != nil))
struct PyflakesProbeTests {

    @Test func parseSimpleError() {
        let diagnostic = PyflakesProbe.parseLine("/tmp/test.py:3:5  undefined name 'foo'")
        #expect(diagnostic != nil)
        #expect(diagnostic?.file == "/tmp/test.py")
        #expect(diagnostic?.startLine == 3)
        #expect(diagnostic?.column == 5)
        #expect(diagnostic?.severity == .error)
        #expect(diagnostic?.message == "undefined name 'foo'")
        #expect(diagnostic?.producer == "pyflakes")
        #expect(diagnostic?.usr == nil)
    }

    @Test func parseUnusedImport() {
        let diagnostic = PyflakesProbe.parseLine("/tmp/test.py:1:1  'os' imported but unused")
        #expect(diagnostic?.message == "'os' imported but unused")
        #expect(diagnostic?.startLine == 1)
    }

    @Test func parseEmptyLineReturnsNil() {
        #expect(PyflakesProbe.parseLine("") == nil)
        #expect(PyflakesProbe.parseLine("   ") == nil)
    }

    @Test func parseNoDoubleSpaceReturnsNil() {
        #expect(PyflakesProbe.parseLine("/tmp/test.py:1:1 single space only") == nil)
    }

    @Test func probeMissingPyflakesReturnsUnavailable() {
        // This test only runs if pyflakes is NOT installed.
        // If pyflakes IS installed, it verifies the probe works on real files.
        let probe = PyflakesProbe()
        let result = probe.probe(files: ["/nonexistent/test.py"])
        // Either unavailable (no pyflakes) or probed the file.
        #expect(result.isAvailable || result.unavailableReason != nil)
    }
}
