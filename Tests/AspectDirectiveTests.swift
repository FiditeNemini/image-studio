@testable import MLXBits_Image_Studio
import Testing

@Suite("AspectDirective")
struct AspectDirectiveTests {
    @Test func noDirectiveLeavesPromptUntouched() {
        let text = "  a red dress\n\nsecond paragraph "
        let result = AspectDirective.extract(from: text)
        #expect(result.prompt == text)
        #expect(result.ratio == nil)
    }

    @Test func stripsLeadingDirectiveLine() {
        let result = AspectDirective.extract(from: "@aspect 3:2\nmissionary, side view")
        #expect(result.prompt == "missionary, side view")
        #expect(result.ratio == 1.5)
    }

    @Test func acceptsSpellingVariants() {
        #expect(AspectDirective.extract(from: "@ASPECT 16x9\nx").ratio == 16.0 / 9.0)
        #expect(AspectDirective.extract(from: "  @aspect=2:3  \nx").ratio == 2.0 / 3.0)
        #expect(AspectDirective.extract(from: "@aspect: 9 : 16\nx").ratio == 9.0 / 16.0)
        #expect(AspectDirective.extract(from: "@aspect 2.39:1\nx").ratio == 2.39)
        #expect(AspectDirective.extract(from: "x\r\n@aspect 4:3").prompt == "x")
    }

    @Test func malformedDirectiveIsStrippedButIgnored() {
        let result = AspectDirective.extract(from: "@aspect wide\na prompt")
        #expect(result.prompt == "a prompt")
        #expect(result.ratio == nil)
        #expect(AspectDirective.extract(from: "@aspect 0:1\nx").ratio == nil)
    }

    @Test func lastDirectiveWins() {
        #expect(AspectDirective.extract(from: "@aspect 3:2\nx\n@aspect 3:4").ratio == 0.75)
    }

    @Test func inlineMentionIsNotADirective() {
        let text = "set @aspect 3:2 later\n@aspectual framing"
        let result = AspectDirective.extract(from: text)
        #expect(result.prompt == text)
        #expect(result.ratio == nil)
    }

    @Test func eachBatchSegmentCarriesItsOwn() {
        let segments = PromptBatchSplitter.split("@aspect 3:2\none\n---\n@aspect 2:3\ntwo\n---\nthree")
        let parsed = segments.map { AspectDirective.extract(from: $0) }
        #expect(parsed.map(\.prompt) == ["one", "two", "three"])
        #expect(parsed.map(\.ratio) == [1.5, 2.0 / 3.0, nil])
    }

    // MARK: - Sizing

    @Test func noRatioMeansNoOverride() {
        #expect(AspectDirective.size(ratio: nil, width: 1024, height: 1024, constraints: .flux2) == nil)
    }

    @Test func matchingRatioKeepsGUISize() {
        let size = AspectDirective.size(ratio: 1.5, width: 1248, height: 832, constraints: .flux2)
        #expect(size?.width == 1248 && size?.height == 832)
    }

    @Test func flippedOrientationSwapsAxes() {
        let size = AspectDirective.size(ratio: 2.0 / 3.0, width: 1536, height: 1024, constraints: .krea2)
        #expect(size?.width == 1024 && size?.height == 1536)
    }

    /// The GUI's area is the target, not the settings default: a draft-size panel
    /// stays draft-size, a large one stays large.
    @Test func keepsGUIArea() throws {
        for (w, h) in [(512, 512), (1024, 1024), (2048, 2048)] {
            let size = try #require(AspectDirective.size(ratio: 16.0 / 9.0, width: w, height: h, constraints: .krea2))
            let area = Double(size.width * size.height)
            #expect(abs(area - Double(w * h)) / Double(w * h) < 0.05)
            #expect(abs(Double(size.width) / Double(size.height) - 16.0 / 9.0) < 0.03)
            #expect(size.width % 16 == 0 && size.height % 16 == 0)
        }
    }

    @Test func respectsFamilyConstraints() throws {
        let size = try #require(AspectDirective.size(ratio: 21.0 / 9.0, width: 2048, height: 2048, constraints: .flux2))
        #expect(size.width * size.height <= 2048 * 2048)
        #expect(size.width % 32 == 0 && size.height % 32 == 0)
    }
}
