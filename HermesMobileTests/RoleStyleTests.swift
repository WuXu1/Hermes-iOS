import Testing
@testable import HermesMobile

struct RoleStyleTests {
    @Test func knownRolesHaveFixedSymbolsAndNames() {
        #expect(RoleStyle.forProfile("researcher").symbol == "magnifyingglass")
        #expect(RoleStyle.forProfile("researcher").displayName == "Researcher")
        #expect(RoleStyle.forProfile("operator").symbol == "safari")
        #expect(RoleStyle.forProfile("coder").symbol == "chevron.left.forwardslash.chevron.right")
        #expect(RoleStyle.forProfile("reviewer").symbol == "checkmark.seal")
        #expect(RoleStyle.forProfile("default").displayName == "Chief of staff")
        #expect(RoleStyle.forProfile("default").symbol == "sparkles")
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
