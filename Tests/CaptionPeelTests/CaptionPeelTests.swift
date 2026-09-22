import XCTest
@testable import CaptionPeel

final class CaptionPeelTests: XCTestCase {
    func testVisionRegionFlipsTopLeftSelectionToVisionCoordinates() {
        let region = VisionOCRRecognizer.visionRegion(for: .init(x: 0.12, y: 0.68, width: 0.76, height: 0.21))

        XCTAssertEqual(region.minX, 0.12, accuracy: 0.0001)
        XCTAssertEqual(region.minY, 0.11, accuracy: 0.0001)
        XCTAssertEqual(region.width, 0.76, accuracy: 0.0001)
        XCTAssertEqual(region.height, 0.21, accuracy: 0.0001)
    }

    func testSRTTimecodeFormattingRoundsToMilliseconds() {
        XCTAssertEqual(Timecode.string(from: 3_661.2346), "01:01:01,235")
        XCTAssertEqual(Timecode.string(from: -1), "00:00:00,000")
    }

    func testTimecodeParsingAcceptsSRTAndEditorSeparators() {
        XCTAssertEqual(Timecode.parse("01:02:03,500"), 3_723.5)
        XCTAssertEqual(Timecode.parse("00:00:12.250"), 12.25)
        XCTAssertNil(Timecode.parse("00:70:00.000"))
    }

    func testSimilarityTreatsMinorOCRDifferencesAsSameCaption() {
        XCTAssertGreaterThan(TextSimilarity.score("Grüezi mitenand!", "Grüezi mitenand."), 0.85)
        XCTAssertLessThan(TextSimilarity.score("Das isch guet", "Morn regnet's"), 0.5)
    }

    func testSRTRenderingSortsCuesAndPreservesMultipleLines() {
        let cues = [
            CaptionCue(start: 5, end: 7.25, text: "Zweite Zeile", confidence: 0.9),
            CaptionCue(start: 1.2, end: 3.4, text: "Grüezi\nmitenand", confidence: 0.95)
        ]

        XCTAssertEqual(
            SRTExporter.render(cues),
            """
            1
            00:00:01,200 --> 00:00:03,400
            Grüezi
            mitenand

            2
            00:00:05,000 --> 00:00:07,250
            Zweite Zeile
            
            """
        )
    }

    func testNormalizedCropStaysInsideVideo() {
        let crop = NormalizedRect(x: -0.2, y: 0.95, width: 1.4, height: 0.2).clamped()
        XCTAssertEqual(crop.x, 0)
        XCTAssertEqual(crop.y, 0.8, accuracy: 0.0001)
        XCTAssertEqual(crop.width, 1)
        XCTAssertEqual(crop.height, 0.2, accuracy: 0.0001)
    }
}
