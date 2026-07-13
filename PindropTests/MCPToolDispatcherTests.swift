import Testing
@testable import Pindrop

@MainActor
@Suite(.serialized)
struct MCPToolDispatcherTests {
    @Test func transcribeSchemaExposesExpectedSpeakerCount() throws {
        let definition = try #require(
            MCPToolDispatcher.allToolDefinitions().first { $0.name == "transcribe" }
        )
        let property = try #require(definition.inputSchema.properties["expected_speakers"])
        #expect(property.type == "integer")
        #expect(property.description.contains("1–20"))
    }

    @Test func jobOptionsPreserveAutomaticDefaults() {
        let options = TranscriptionJobOptions(modelName: "tiny")
        #expect(options.diarizationEnabled)
        #expect(options.expectedSpeakerCount == nil)
    }

    @Test(arguments: [1, 2, 20])
    func acceptedSpeakerCountsAreRepresentable(_ count: Int) {
        let options = TranscriptionJobOptions(modelName: "tiny", expectedSpeakerCount: count)
        #expect(options.expectedSpeakerCount == count)
    }
}
