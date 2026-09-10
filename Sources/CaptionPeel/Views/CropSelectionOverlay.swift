import SwiftUI

struct CropSelectionOverlay: View {
    @Binding var selection: NormalizedRect
    @State private var moveStart: NormalizedRect?
    @State private var resizeStart: NormalizedRect?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let crop = CGRect(
                x: selection.x * size.width,
                y: selection.y * size.height,
                width: selection.width * size.width,
                height: selection.height * size.height
            )

            ZStack(alignment: .topLeading) {
                dimmedArea(around: crop, in: size)

                // Position the hit target and border in the same coordinate space.
                // Applying an overlay after `offset` leaves the overlay at the
                // GeometryReader origin on macOS.
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: crop.width, height: crop.height)
                    .position(x: crop.midX, y: crop.midY)
                    .gesture(moveGesture(in: size))

                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: crop.width, height: crop.height)
                    .position(x: crop.midX, y: crop.midY)
                    .allowsHitTesting(false)

                handle(.topLeft, at: CGPoint(x: crop.minX, y: crop.minY), size: size)
                handle(.topRight, at: CGPoint(x: crop.maxX, y: crop.minY), size: size)
                handle(.bottomLeft, at: CGPoint(x: crop.minX, y: crop.maxY), size: size)
                handle(.bottomRight, at: CGPoint(x: crop.maxX, y: crop.maxY), size: size)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Caption region")
            .accessibilityValue("Selected region in the video")
        }
    }

    @ViewBuilder
    private func dimmedArea(around crop: CGRect, in size: CGSize) -> some View {
        let shade = Color.black.opacity(0.48)
        Rectangle().fill(shade).frame(width: size.width, height: max(0, crop.minY))
        Rectangle().fill(shade)
            .frame(width: size.width, height: max(0, size.height - crop.maxY))
            .offset(y: crop.maxY)
        Rectangle().fill(shade)
            .frame(width: max(0, crop.minX), height: crop.height)
            .offset(y: crop.minY)
        Rectangle().fill(shade)
            .frame(width: max(0, size.width - crop.maxX), height: crop.height)
            .offset(x: crop.maxX, y: crop.minY)
    }

    private func moveGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if moveStart == nil { moveStart = selection }
                guard let start = moveStart, size.width > 0, size.height > 0 else { return }
                selection = NormalizedRect(
                    x: start.x + value.translation.width / size.width,
                    y: start.y + value.translation.height / size.height,
                    width: start.width,
                    height: start.height
                ).clamped()
            }
            .onEnded { _ in moveStart = nil }
    }

    private func handle(_ corner: Corner, at point: CGPoint, size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                .frame(width: 14, height: 14)
        }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .position(point)
            .gesture(resizeGesture(corner, in: size))
            .accessibilityLabel("Resize caption region")
    }

    private func resizeGesture(_ corner: Corner, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if resizeStart == nil { resizeStart = selection }
                guard let start = resizeStart, size.width > 0, size.height > 0 else { return }
                let dx = value.translation.width / size.width
                let dy = value.translation.height / size.height
                let minSize = 0.04
                let right = start.x + start.width
                let bottom = start.y + start.height
                var next = start

                switch corner {
                case .topLeft:
                    next.x = min(max(0, start.x + dx), right - minSize)
                    next.y = min(max(0, start.y + dy), bottom - minSize)
                    next.width = right - next.x
                    next.height = bottom - next.y
                case .topRight:
                    next.y = min(max(0, start.y + dy), bottom - minSize)
                    next.width = min(max(minSize, start.width + dx), 1 - start.x)
                    next.height = bottom - next.y
                case .bottomLeft:
                    next.x = min(max(0, start.x + dx), right - minSize)
                    next.width = right - next.x
                    next.height = min(max(minSize, start.height + dy), 1 - start.y)
                case .bottomRight:
                    next.width = min(max(minSize, start.width + dx), 1 - start.x)
                    next.height = min(max(minSize, start.height + dy), 1 - start.y)
                }
                selection = next.clamped()
            }
            .onEnded { _ in resizeStart = nil }
    }

    private enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }
}
