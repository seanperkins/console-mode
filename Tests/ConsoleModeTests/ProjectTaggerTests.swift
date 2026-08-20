import Foundation
import Testing
@testable import ConsoleModeKit

// Payload shapes below mirror real LM Studio responses captured from
// ornith-1.5-9b-mlx while building this feature.

@Test func parsesVerdictFromContent() throws {
    let data = Data("""
    {"choices":[{"message":{"content":"{\\"project\\": \\"console-mode\\", \\"confidence\\": 0.95}"}}]}
    """.utf8)

    let verdict = try ProjectTagger.parseVerdict(data: data, minimumConfidence: 0.5)
    #expect(verdict.project == "console-mode")
    #expect(verdict.confidence == 0.95)
}

/// Ornith emits JSON inside its thinking block, leaving `content` empty.
@Test func fallsBackToReasoningContent() throws {
    let data = Data("""
    {"choices":[{"message":{"content":"","reasoning_content":"{ \\"project\\": \\"freshbooks-mcp\\", \\"confidence\\": 0.95 }"}}]}
    """.utf8)

    let verdict = try ProjectTagger.parseVerdict(data: data, minimumConfidence: 0.5)
    #expect(verdict.project == "freshbooks-mcp")
}

@Test func emptyProjectMeansNoLabel() throws {
    let data = Data("""
    {"choices":[{"message":{"content":"","reasoning_content":"{ \\"project\\": \\"\\", \\"confidence\\": 0.1 }"}}]}
    """.utf8)

    let verdict = try ProjectTagger.parseVerdict(data: data, minimumConfidence: 0.5)
    #expect(verdict.project == nil)
    #expect(verdict.confidence == 0.1)
}

@Test func confidenceBelowThresholdIsDiscarded() throws {
    let verdict = try ProjectTagger.parseVerdict(
        payload: "{\"project\": \"maybe-thing\", \"confidence\": 0.3}",
        minimumConfidence: 0.5
    )
    #expect(verdict.project == nil)
    #expect(verdict.confidence == 0.3)
}

@Test func serverErrorSurfacesAsUndecodable() {
    let data = Data("{\"error\":\"'type' must be a string\"}".utf8)
    #expect(throws: ProjectTagger.TaggerError.self) {
        try ProjectTagger.parseVerdict(data: data, minimumConfidence: 0.5)
    }
}

@Test func extractsJSONWrappedInProse() throws {
    let verdict = try ProjectTagger.parseVerdict(
        payload: "Sure! ```json\n{\"project\": \"event-calendar\", \"confidence\": 0.8}\n``` done",
        minimumConfidence: 0.5
    )
    #expect(verdict.project == "event-calendar")
}

@Test func normalizesLabelsToStableSlugs() {
    #expect(ProjectTagger.normalize("Console Mode") == "console-mode")
    #expect(ProjectTagger.normalize("  ConsoleMode  ") == "consolemode")
    #expect(ProjectTagger.normalize("event_calendar") == "event-calendar")
    #expect(ProjectTagger.normalize("Foo / Bar") == "foo-bar")
}

@Test func normalizeRejectsNoLabelSentinels() {
    #expect(ProjectTagger.normalize("") == nil)
    #expect(ProjectTagger.normalize("  ") == nil)
    #expect(ProjectTagger.normalize("none") == nil)
    #expect(ProjectTagger.normalize("N/A") == nil)
    #expect(ProjectTagger.normalize("unknown") == nil)
    #expect(ProjectTagger.normalize("---") == nil)
}

@Test func completionsURLTolerantOfBaseFormats() {
    var config = TaggerConfig.standard

    for base in [
        "http://127.0.0.1:1234",
        "http://127.0.0.1:1234/",
        "http://127.0.0.1:1234/v1",
        "http://127.0.0.1:1234/v1/chat/completions",
    ] {
        config.baseURL = base
        #expect(config.completionsURL.absoluteString == "http://127.0.0.1:1234/v1/chat/completions")
    }
}

@Test func requestBodyPinsModelAndSchema() {
    let tagger = ProjectTagger(config: .standard)
    let body = tagger.requestBody(for: "ship it", knownProjects: ["console-mode"])

    #expect(body["model"] as? String == "ornith-1.5-9b-mlx")
    #expect(body["temperature"] as? Int == 0)

    // Union types are rejected by the MLX backend, so project must stay a plain string.
    let format = body["response_format"] as? [String: Any]
    let schema = (format?["json_schema"] as? [String: Any])?["schema"] as? [String: Any]
    let properties = schema?["properties"] as? [String: Any]
    let project = properties?["project"] as? [String: Any]
    #expect(project?["type"] as? String == "string")

    let prompt = ProjectTagger.userPrompt(body: "ship it", knownProjects: ["console-mode", "x"])
    #expect(prompt.contains("known_projects: [\"console-mode\", \"x\"]"))
    #expect(prompt.contains("note: \"ship it\""))
}
