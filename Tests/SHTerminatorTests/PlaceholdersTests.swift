import Testing
@testable import SHTerminator

@Suite struct PlaceholdersTests {
    @Test func noPlaceholders() {
        #expect(Placeholders.fields(in: "ssh prod").isEmpty)
        #expect(Placeholders.fill("ssh prod", with: [:]) == "ssh prod")
    }

    @Test func fieldsAreDistinctInOrderWithDefaults() {
        let command = "psql -h {{host:db.internal}} -U {{ user }} {{db}} # {{user}}"
        #expect(Placeholders.fields(in: command) == [
            .init(name: "host", defaultValue: "db.internal"),
            .init(name: "user", defaultValue: ""),
            .init(name: "db", defaultValue: ""),
        ])
    }

    @Test func fillReplacesEveryOccurrenceAndFallsBackToDefault() {
        let command = "scp {{file}} {{host:box}}:/tmp/{{file}}"
        #expect(Placeholders.fill(command, with: ["file": "a.txt"]) == "scp a.txt box:/tmp/a.txt")
    }

    @Test func defaultMayContainColons() {
        #expect(Placeholders.fields(in: "{{url:http://x:8080}}") == [.init(name: "url", defaultValue: "http://x:8080")])
    }
}
