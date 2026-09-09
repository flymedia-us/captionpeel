import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        Group {
            switch model.state {
            case .empty:
                EmptyStateView()
            case .setup:
                SetupView()
            case .processing:
                ProcessingView()
            case .results:
                ResultsView()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Image(systemName: "captions.bubble.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("CaptionPeel")
                        .fontWeight(.semibold)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Open Video…") { model.presentOpenPanel() }
            }
        }
        .onOpenURL { url in
            model.loadVideo(url)
        }
        .alert("CaptionPeel", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "An unexpected error occurred.")
        }
    }
}

private struct EmptyStateView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "captions.bubble")
                .font(.system(size: 62, weight: .light))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 7) {
                Text("Turn burned-in captions into SRT")
                    .font(.title2.weight(.semibold))
                Text("Drop a video here. Everything stays on your Mac.")
                    .foregroundStyle(.secondary)
            }
            Button("Open Video…") { model.presentOpenPanel() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer()
            Text("Native • Private • Open Source")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [9]))
                .padding(24)
                .opacity(isTargeted ? 1 : 0)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.loadVideo(url)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

private struct SetupView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text(model.fileName)
                    .font(.headline)
                    .lineLimit(1)
                Text("Move and resize the box around the caption area")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VideoWorkspaceView(allowsCropEditing: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            DisclosureGroup("Scan range") {
                HStack {
                    Toggle("Process only part of the video", isOn: $model.scanRangeEnabled)
                    Spacer()
                    if model.scanRangeEnabled {
                        Text("\(Timecode.string(from: model.scanStart, decimalSeparator: ".")) – \(Timecode.string(from: model.scanEnd, decimalSeparator: "."))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                if model.scanRangeEnabled {
                    HStack {
                        Text("Start")
                        Slider(value: $model.scanStart, in: 0...max(model.scanEnd - 0.1, 0.1))
                        Text("End")
                        Slider(value: $model.scanEnd, in: min(model.scanStart + 0.1, model.duration)...max(model.duration, 0.2))
                    }
                    .font(.caption)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))

            HStack {
                Text("Only the selected area will be analyzed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Extract Captions") { model.extractCaptions() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.duration <= 0 || (model.scanRangeEnabled && model.scanEnd - model.scanStart < 0.1))
            }
        }
        .padding(24)
    }
}

private struct ProcessingView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(spacing: 22) {
            Text(model.fileName)
                .font(.headline)
            VideoWorkspaceView(allowsCropEditing: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0.72)
                .allowsHitTesting(false)

            VStack(spacing: 10) {
                HStack {
                    Text(model.extractionProgress.phase.rawValue)
                        .fontWeight(.medium)
                    Spacer()
                    Text(model.extractionProgress.fraction, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: model.extractionProgress.fraction)
                HStack {
                    Text("Processing locally with Apple Vision")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", role: .cancel) { model.cancelExtraction() }
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(24)
    }
}
