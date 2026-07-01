import Testing
import Foundation
import SwiftData
@testable import LSM

struct RosterCSVTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: RosterMember.self, PlayerGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

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

    // MARK: - serialize

    @Test func serializesMemberWithNoGroupsAsBareName() throws {
        let context = try makeContext()
        let dave = RosterMember(name: "Dave")
        context.insert(dave)
        #expect(RosterCSV.serialize([dave]) == "Dave")
    }

    @Test func serializesMemberWithOneGroup() throws {
        let context = try makeContext()
        let work = PlayerGroup(name: "Work")
        context.insert(work)
        let dave = RosterMember(name: "Dave")
        dave.groups = [work]
        context.insert(dave)
        #expect(RosterCSV.serialize([dave]) == "Dave, Work")
    }

    @Test func serializesMemberInMultipleGroupsAsOneRowPerGroup() throws {
        let context = try makeContext()
        let family = PlayerGroup(name: "Family")
        let work = PlayerGroup(name: "Work")
        context.insert(family)
        context.insert(work)
        let dave = RosterMember(name: "Dave")
        dave.groups = [work, family]
        context.insert(dave)
        #expect(RosterCSV.serialize([dave]) == "Dave, Family\nDave, Work")
    }

    @Test func serializeSortsByMemberNameThenGroupName() throws {
        let context = try makeContext()
        let work = PlayerGroup(name: "Work")
        context.insert(work)
        let sarah = RosterMember(name: "Sarah")
        let dave = RosterMember(name: "Dave")
        dave.groups = [work]
        context.insert(sarah)
        context.insert(dave)
        #expect(RosterCSV.serialize([sarah, dave]) == "Dave, Work\nSarah")
    }

    @Test func serializeOfEmptyListIsEmptyString() {
        #expect(RosterCSV.serialize([]) == "")
    }

    @Test func parseAndSerializeRoundTripPreservesNameAndGroupMembership() throws {
        let context = try makeContext()
        let work = PlayerGroup(name: "Work")
        let family = PlayerGroup(name: "Family")
        context.insert(work)
        context.insert(family)
        let dave = RosterMember(name: "Dave")
        dave.groups = [work, family]
        let sarah = RosterMember(name: "Sarah")
        context.insert(dave)
        context.insert(sarah)

        let csv = RosterCSV.serialize([dave, sarah])
        let rows = RosterCSV.parse(csv)

        #expect(rows == [
            .init(name: "Dave", group: "Family"),
            .init(name: "Dave", group: "Work"),
            .init(name: "Sarah", group: nil),
        ])
    }
}
