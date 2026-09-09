@preconcurrency import AVFoundation
import SwiftUI

struct VideoWorkspaceView: View {
    @EnvironmentObject private var model: AppViewModel
    var allowsCropEditing: Bool

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let videoRect = aspectFitRect(content: model.videoSize, in: geometry.size)
                ZStack {
                    Color.black
                    PlayerSurface(player: model.player)

                    if allowsCropEditing {
                        CropSelectionOverlay(selection: $model.captionRegion)
                            .frame(width: videoRect.width, height: videoRect.height)
                            .position(x: videoRect.midX, y: videoRect.midY)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .aspectRatio(max(model.videoSize.width, 1) / max(model.videoSize.height, 1), contentMode: .fit)

            PlaybackControls()
        }
    }

    private func aspectFitRect(content: CGSize, in container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / content.width, container.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

private struct PlaybackControls: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")

            Slider(
                value: Binding(
                    get: { model.currentTime },
                    set: { model.seek(to: $0) }
                ),
                in: 0...max(model.duration, 0.01)
            )

            Text("\(Timecode.string(from: model.currentTime, decimalSeparator: ".")) / \(Timecode.string(from: model.duration, decimalSeparator: "."))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 4)
    }
}
