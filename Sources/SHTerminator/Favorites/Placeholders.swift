import AppKit

/// `{{name}}` / `{{name:default}}` fields in a favorite's command, filled in
/// by the user each time it is inserted — e.g.
/// `psql -h {{host:db.internal}} -U {{user}} {{database}}`.
enum Placeholders {
    struct Field: Equatable {
        var name: String
        var defaultValue: String
    }

    private static let pattern = try! NSRegularExpression(pattern: #"\{\{\s*([^{}:]+?)\s*(?::([^{}]*))?\}\}"#)

    /// Distinct fields in order of first appearance; the first default
    /// given for a name wins.
    static func fields(in command: String) -> [Field] {
        var fields: [Field] = []
        for match in matches(in: command) where !fields.contains(where: { $0.name == match.name }) {
            fields.append(Field(name: match.name, defaultValue: match.defaultValue))
        }
        return fields
    }

    /// `command` with every placeholder replaced by `values[name]`.
    static func fill(_ command: String, with values: [String: String]) -> String {
        var result = command
        for match in matches(in: command).reversed() {
            result.replaceSubrange(match.range, with: values[match.name] ?? match.defaultValue)
        }
        return result
    }

    private static func matches(in command: String) -> [(range: Range<String.Index>, name: String, defaultValue: String)] {
        let all = NSRange(command.startIndex..., in: command)
        return pattern.matches(in: command, range: all).compactMap { match in
            guard let range = Range(match.range, in: command),
                  let nameRange = Range(match.range(at: 1), in: command) else { return nil }
            let defaultValue = Range(match.range(at: 2), in: command).map { String(command[$0]) } ?? ""
            return (range, String(command[nameRange]), defaultValue)
        }
    }

    /// Asks for the fields' values in a sheet on `window` (if there are any),
    /// then hands the filled-in command to `completion`. Cancel calls nothing.
    @MainActor
    static func resolve(_ command: String, in window: NSWindow, completion: @escaping (String) -> Void) {
        let fields = fields(in: command)
        guard !fields.isEmpty else {
            completion(command)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Fill in the command"
        alert.informativeText = command
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")
        alert.window.sharingType = .none

        let grid = NSGridView()
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        var inputs: [NSTextField] = []
        for field in fields {
            let input = NSTextField(string: field.defaultValue)
            input.placeholderString = field.name
            input.widthAnchor.constraint(equalToConstant: 240).isActive = true
            grid.addRow(with: [NSTextField(labelWithString: field.name + ":"), input])
            inputs.append(input)
        }
        grid.column(at: 0).xPlacement = .trailing
        grid.layoutSubtreeIfNeeded()
        grid.frame.size = grid.fittingSize
        alert.accessoryView = grid
        alert.window.initialFirstResponder = inputs.first
        for (input, next) in zip(inputs, inputs.dropFirst()) {
            input.nextKeyView = next
        }

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            var values: [String: String] = [:]
            for (field, input) in zip(fields, inputs) {
                values[field.name] = input.stringValue
            }
            completion(fill(command, with: values))
        }
    }
}
