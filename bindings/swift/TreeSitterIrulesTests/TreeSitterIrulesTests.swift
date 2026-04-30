import XCTest
import SwiftTreeSitter
import TreeSitterIrules

final class TreeSitterIrulesTests: XCTestCase {
    func testCanLoadGrammar() throws {
        let parser = Parser()
        let language = Language(language: tree_sitter_irules())
        XCTAssertNoThrow(try parser.setLanguage(language),
                         "Error loading iRules grammar")
    }
}
