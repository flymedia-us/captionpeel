@preconcurrency import AVFoundation
import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    enum AppState: Equatable {
        case empty
        case setup
        case processing
        case results
    }

    @Published var state: AppState = .empty
    @Published var videoURL: URL?
    @Published var videoSize = CGSize(width: 16, height: 9)
    @Published var duration: TimeInterval = 0
    @Published var currentTime: TimeInterval = 0
    @Published var isPlaying = false
    @Published var captionRegion = NormalizedRect.suggestedCaptionRegion
    @Published var extractionProgress = ExtractionProgress(fraction: 0, phase: .preparing, currentTime: 0, duration: 0)
    @Published var cues: [CaptionCue] = []
    @Published var selectedCueID: UUID?
    @Published var errorMessage: String?
    @Published var scanRangeEnabled = false
    @Published var scanStart: TimeInterval = 0
    @Published var scanEnd: TimeInterval = 0
    @Published var isRereading = false

    let player = AVPlayer()

    private var timeObserver: PlayerTimeObserverToken?
    private var extractionTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var securityScopedVideoURL: URL?

    init() {
        timeObserver = PlayerTimeObserverToken(
            player: player,
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = max(0, time.seconds.isFinite ? time.seconds : 0)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = seconds
                self.isPlaying = self.player.rate != 0
            }
        }
    }

    deinit {
        securityScopedVideoURL?.stopAccessingSecurityScopedResource()
    }

    var fileName: String {
        videoURL?.lastPathComponent ?? "Video"
    }

    var selectedCueIndex: Int? {
        guard let selectedCueID else { return nil }
        return cues.firstIndex { $0.id == selectedCueID }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open a Video"
        panel.prompt = "Open Video"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .audiovisualContent]
        if panel.runModal() == .OK, let url = panel.url {
            loadVideo(url)
        }
    }

    func loadVideo(_ url: URL) {
        guard url.isFileURL else {
            errorMessage = "Please choose a video file from this Mac."
            return
        }

        cancelExtraction()
        metadataTask?.cancel()
        player.pause()
        securityScopedVideoURL?.stopAccessingSecurityScopedResource()
        securityScopedVideoURL = url.startAccessingSecurityScopedResource() ? url : nil
        videoURL = url
        cues = []
        selectedCueID = nil
        captionRegion = .suggestedCaptionRegion
        state = .setup

        let asset = AVURLAsset(url: url)
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))

        metadataTask = Task { [weak self] in
            do {
                let loadedDuration = try await asset.load(.duration).seconds
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let track = tracks.first else { throw ExtractionError.frameUnavailable }
                let naturalSize = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let transformed = naturalSize.applying(transform)
                try Task.checkCancellation()
                self?.duration = loadedDuration.isFinite ? loadedDuration : 0
                self?.scanStart = 0
                self?.scanEnd = loadedDuration.isFinite ? loadedDuration : 0
                self?.videoSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
            } catch is CancellationError {
                return
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func togglePlayback() {
        if player.rate == 0 {
            if duration > 0, currentTime >= duration - 0.05 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
    }

    func seek(to seconds: TimeInterval) {
        let clamped = min(max(0, seconds), duration)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }

    func selectCue(_ cue: CaptionCue) {
        selectedCueID = cue.id
        seek(to: cue.start)
    }

    func extractCaptions() {
        guard let videoURL, duration > 0 else { return }
        player.pause()
        state = .processing
        extractionProgress = ExtractionProgress(fraction: 0, phase: .preparing, currentTime: 0, duration: duration)

        let region = captionRegion
        let range: ClosedRange<TimeInterval>? = scanRangeEnabled
            ? min(scanStart, scanEnd)...max(scanStart, scanEnd)
            : nil
        let engine = CaptionExtractionEngine(videoURL: videoURL)
        let progressBridge = ExtractionProgressBridge(model: self)

        extractionTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let extracted = try await engine.extract(region: region, range: range) { update in
                    progressBridge.send(update)
                }
                try Task.checkCancellation()
                await MainActor.run { [weak self] in
                    self?.cues = extracted
                    self?.selectedCueID = extracted.first?.id
                    self?.state = .results
                    if let first = extracted.first { self?.seek(to: first.start) }
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    self?.state = .setup
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.state = .setup
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func cancelExtraction() {
        extractionTask?.cancel()
        extractionTask = nil
        if state == .processing { state = .setup }
    }

    func returnToSetup() {
        state = .setup
    }

    func deleteSelectedCue() {
        guard let index = selectedCueIndex else { return }
        cues.remove(at: index)
        selectedCueID = cues.indices.contains(index) ? cues[index].id : cues.last?.id
    }

    func mergeSelectedWithNext() {
        guard let index = selectedCueIndex, cues.indices.contains(index + 1) else { return }
        let next = cues[index + 1]
        cues[index].end = max(cues[index].end, next.end)
        let left = cues[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = next.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if TextSimilarity.score(left, right) < 0.78 {
            cues[index].text = [left, right].filter { !$0.isEmpty }.joined(separator: "\n")
        } else if next.confidence > cues[index].confidence {
            cues[index].text = next.text
            cues[index].confidence = next.confidence
        }
        cues.remove(at: index + 1)
    }

    func rereadSelectedCue() {
        guard let videoURL, let index = selectedCueIndex, !isRereading else { return }
        isRereading = true
        let cueID = cues[index].id
        let time = (cues[index].start + cues[index].end) / 2
        let region = captionRegion
        let engine = CaptionExtractionEngine(videoURL: videoURL)

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let result = try await engine.recognize(at: time, region: region)
                await MainActor.run { [weak self] in
                    guard let self, let currentIndex = self.cues.firstIndex(where: { $0.id == cueID }) else { return }
                    if !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.cues[currentIndex].text = result.text
                        self.cues[currentIndex].confidence = result.confidence
                    }
                    self.isRereading = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isRereading = false
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func presentSavePanel() {
        guard !cues.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "Export Captions"
        panel.prompt = "Export SRT"
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = (videoURL?.deletingPathExtension().lastPathComponent ?? "captions") + ".srt"
        if panel.runModal() == .OK, var url = panel.url {
            if url.pathExtension.lowercased() != "srt" {
                url.appendPathExtension("srt")
            }
            do {
                try SRTExporter.write(cues, to: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private final class PlayerTimeObserverToken: @unchecked Sendable {
    private weak var player: AVPlayer?
    private var token: Any?

    init(
        player: AVPlayer,
        forInterval interval: CMTime,
        queue: DispatchQueue,
        callback: @escaping @Sendable (CMTime) -> Void
    ) {
        self.player = player
        token = player.addPeriodicTimeObserver(forInterval: interval, queue: queue, using: callback)
    }

    deinit {
        if let token {
            player?.removeTimeObserver(token)
        }
    }
}

private final class ExtractionProgressBridge: @unchecked Sendable {
    private weak var model: AppViewModel?

    @MainActor
    init(model: AppViewModel) {
        self.model = model
    }

    func send(_ update: ExtractionProgress) {
        Task { @MainActor [weak self] in
            self?.model?.extractionProgress = update
        }
    }
}
