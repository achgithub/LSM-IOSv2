import Testing
import Foundation
@testable import LSM

struct RosterCSVTests {

    @Test func parsesNamesWithNoGroup() {
        let rows = RosterCSV.parse("Dave\nSarah\nPete")
        #expect(rows == [.init(name: "Dave", group: nil),
                         .init(name: "Sarah", group: nil),
                         .init(name: "Pete", group: nil)])
    }

    @Test func parsesPerRowGroup() {
        let rows = RosterCSV.parse("Dave, Work\nSarah, Family")
        #expect(rows == [.init(name: "Dave", group: "Work"),
                         .init(name: "Sarah", group: "Family")])
    }

    @Test func legacyNameEmailStillWorksWithNoGroup() {
        let rows = RosterCSV.parse("Dave, dave@example.com\nSarah,sarah@x.io")
        #expect(rows == [.init(name: "Dave", group: nil),
                         .init(name: "Sarah", group: nil)])
    }

    @Test func resolvesGroupAfterEmailColumn() {
        let rows = RosterCSV.parse("Pete, pete@x.io, Work")
        #expect(rows == [.init(name: "Pete", group: "Work")])
    }

    @Test func trimsWhitespaceAndSkipsBlankRows() {
        let rows = RosterCSV.parse("  Dave , Work  \n\n   \nSarah\n")
        #expect(rows == [.init(name: "Dave", group: "Work"),
                         .init(name: "Sarah", group: nil)])
    }

    @Test func handlesCarriageReturnsAndEmptyInput() {
        #expect(RosterCSV.parse("Dave\r\nSarah") == [.init(name: "Dave", group: nil),
                                                     .init(name: "Sarah", group: nil)])
        #expect(RosterCSV.parse("") == [])
    }
}
