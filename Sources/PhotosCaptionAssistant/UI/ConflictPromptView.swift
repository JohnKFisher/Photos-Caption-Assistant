import SwiftUI

struct ConflictPromptData: Identifiable {
    let id = UUID()
    let asset: MediaAsset
    let existing: ExistingMetadataState
}

struct ConflictPromptView: View {
    let prompt: ConflictPromptData
    let onDecision: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Overwrite Existing Metadata?")
                .font(.title3.bold())

            Text(prompt.asset.filename)
                .font(.headline)

            GroupBox("Current Caption") {
                Text(prompt.existing.caption?.isEmpty == false ? prompt.existing.caption! : "(empty)")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Current Keywords") {
                if prompt.existing.keywords.isEmpty {
                    Text("(empty)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(prompt.existing.keywords.joined(separator: ", "))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Text("This item has non-app metadata. Choose whether to overwrite it.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Skip") {
                    onDecision(false)
                }
                Button("Overwrite") {
                    onDecision(true)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(minWidth: 420, minHeight: 280)
    }
}
