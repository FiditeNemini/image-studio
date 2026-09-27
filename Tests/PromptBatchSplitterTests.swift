@testable import MLXBits_Image_Studio
import Testing

@Suite("PromptBatchSplitter")
struct PromptBatchSplitterTests {
    @Test func singlePromptIsNotABatch() {
        #expect(PromptBatchSplitter.split("a red dress") == ["a red dress"])
        #expect(!PromptBatchSplitter.isBatch("a red dress\n\nsecond paragraph"))
        #expect(PromptBatchSplitter.split("   \n ").isEmpty)
    }

    @Test func splitsOnDashLines() {
        let text = "first prompt\nline two\n---\nsecond prompt\n  -----  \nthird"
        #expect(PromptBatchSplitter.split(text) == ["first prompt\nline two", "second prompt", "third"])
        #expect(PromptBatchSplitter.isBatch(text))
    }

    @Test func handlesWindowsLineEndings() {
        #expect(PromptBatchSplitter.split("one\r\n---\r\ntwo") == ["one", "two"])
    }

    @Test func ignoresInlineDashesAndShortRuns() {
        #expect(PromptBatchSplitter.split("a --- b") == ["a --- b"])
        #expect(PromptBatchSplitter.split("a\n--\nb") == ["a\n--\nb"])
    }

    @Test func dropsEmptySegments() {
        #expect(PromptBatchSplitter.split("---\none\n---\n---\ntwo\n---\n") == ["one", "two"])
    }

    @Test func keepsWildcardsIntact() {
        #expect(PromptBatchSplitter.split("a {red|blue} dress\n---\nb") == ["a {red|blue} dress", "b"])
    }
}
