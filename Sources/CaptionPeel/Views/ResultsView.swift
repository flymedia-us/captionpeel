import SwiftUI

struct ResultsView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        HSplitView {
            VStack(spacing: 14) {
                Text(model.fileName)
                    .font(.headline)
                    .lineLimit(1)
                VideoWorkspaceView(allowsCropEditing: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(20)
            .frame(minWidth: 440)

            VStack(spacing: 0) {
                resultHeader
                Divider()
                captionList
                Divider()
                resultFooter
            }
            .frame(minWidth: 380, idealWidth: 440)
        }
    }

    private var resultHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Extracted Captions")
                    .font(.headline)
                Text("\(model.cues.count) \(model.cues.count == 1 ? "cue" : "cues")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.returnToSetup()
            } label: {
                Label("Rescan", systemImage: "arrow.counterclockwise")
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var captionList: some View {
        if model.cues.isEmpty {
            ContentUnavailableView(
                "No Captions Found",
                systemImage: "captions.bubble",
                description: Text("Try adjusting the selected region and scan again.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $model.selectedCueID) {
                ForEach($model.cues) { $cue in
                    CaptionCueRow(cue: $cue)
                        .tag(cue.id)
                }
            }
            .onChange(of: model.selectedCueID) { _, newValue in
                guard let newValue, let cue = model.cues.first(where: { $0.id == newValue }) else { return }
                model.seek(to: cue.start)
            }
        }
    }

    private var resultFooter: some View {
        HStack(spacing: 8) {
            Button {
                model.deleteSelectedCue()
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete selected cue")
            .disabled(model.selectedCueIndex == nil)

            Button("Merge Next") { model.mergeSelectedWithNext() }
                .disabled(model.selectedCueIndex.map { $0 >= model.cues.count - 1 } ?? true)

            Button {
                model.rereadSelectedCue()
            } label: {
                if model.isRereading {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Re-read", systemImage: "text.viewfinder")
                }
            }
            .disabled(model.selectedCueIndex == nil || model.isRereading)

            Spacer()
            Button("Export SRT…") { model.presentSavePanel() }
                .buttonStyle(.borderedProminent)
                .disabled(model.cues.isEmpty)
        }
        .padding(12)
    }
}

private struct CaptionCueRow: View {
    @Binding var cue: CaptionCue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TimecodeField(label: "Start", value: $cue.start)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TimecodeField(label: "End", value: $cue.end)
                Spacer()
                if cue.confidence > 0 {
                    Text(cue.confidence, format: .percent.precision(.fractionLength(0)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help("OCR confidence")
                }
            }

            TextEditor(text: $cue.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 42, maxHeight: 72)
                .padding(6)
                .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator.opacity(0.4)))
        }
        .padding(.vertical, 5)
    }
}

private struct TimecodeField: View {
    let label: String
    @Binding var value: TimeInterval
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(label, text: $text)
            .font(.system(.caption, design: .monospaced))
            .textFieldStyle(.roundedBorder)
            .frame(width: 92)
            .focused($isFocused)
            .onAppear { text = Timecode.string(from: value, decimalSeparator: ".") }
            .onSubmit { commit() }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onChange(of: value) { _, newValue in
                if !isFocused { text = Timecode.string(from: newValue, decimalSeparator: ".") }
            }
            .accessibilityLabel(label)
    }

    private func commit() {
        if let parsed = Timecode.parse(text) {
            value = parsed
        }
        text = Timecode.string(from: value, decimalSeparator: ".")
    }
}
