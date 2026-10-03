import Testing
@testable import HermesMobile

struct RoleStyleTests {
    @Test func fiveAgentsHaveFixedStyles() {
        #expect(RoleStyle.forProfile("default").displayName == "Commander")
        #expect(RoleStyle.forProfile("developer").displayName == "Developer")
        #expect(RoleStyle.forProfile("tutor").displayName == "Tutor")
        #expect(RoleStyle.forProfile("assistant").displayName == "Assistant")
        #expect(RoleStyle.forProfile("coach").displayName == "Coach")
        #expect(RoleStyle.forProfile("coach").symbol == "figure.tennis")
    }

    @Test func unknownAgentStillGetsAStyle() {
        #expect(RoleStyle.forProfile("night-owl").displayName == "Night owl")
    }

    @Test func unknownRoleUsesCapitalizedNameAndInitial() {
        let style = RoleStyle.forProfile("data-analyst")
        #expect(style.displayName == "Data analyst")
        #expect(style.symbol == "person.fill")
    }

    @Test func unknownRolePaletteIndexIsStable() {
        let first = RoleStyle.paletteIndex(for: "data-analyst")
        #expect(first == RoleStyle.paletteIndex(for: "data-analyst"))
        #expect((0 ..< RoleStyle.palette.count).contains(first))
        #expect(RoleStyle.paletteIndex(for: "a") != RoleStyle.paletteIndex(for: "b"))
    }

    @Test func missingAssigneeIsUnassigned() {
        #expect(RoleStyle.forProfile(nil).displayName == "Unassigned")
    }
}
