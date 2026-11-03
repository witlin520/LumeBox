import Foundation
import CoreML
import CryptoKit

// Run on the build Mac, never on the user's phone. The model and token IDs
// are the same ones previously used by IntroRecognitionController.
guard CommandLine.arguments.count == 5 else {
  fatalError("usage: precompute_intro_vectors model.mlpackage prompts.json revision output.json")
}
let modelURL = URL(fileURLWithPath: CommandLine.arguments[1])
let promptData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
let prompts = try JSONDecoder().decode([String: [[Int]]].self, from: promptData)
let compiled = try MLModel.compileModel(at: modelURL)
defer { try? FileManager.default.removeItem(at: compiled) }
let config = MLModelConfiguration()
config.computeUnits = .cpuOnly
let model = try MLModel(contentsOf: compiled, configuration: config)
var vectors: [String: [[Double]]] = [:]
var dimension = 0
for label in ["recap", "opening", "main", "ending"] {
  guard let examples = prompts[label], examples.count == 2 else { fatalError("invalid anchor labels") }
  for tokens in examples {
    guard tokens.count == 77 else { fatalError("invalid token count") }
    let input = try MLMultiArray(shape: [1, 77], dataType: .int32)
    for i in 0..<77 { input[i] = NSNumber(value: tokens[i]) }
    let provider = try MLDictionaryFeatureProvider(dictionary: ["text": MLFeatureValue(multiArray: input)])
    let prediction = try model.prediction(from: provider)
    guard let value = prediction.featureValue(for: "final_emb_1")?.multiArrayValue else { fatalError("missing embedding") }
    let vector = (0..<value.count).map { value[$0].doubleValue }
    if dimension == 0 { dimension = vector.count }
    guard vector.count == dimension, vector.allSatisfy({ $0.isFinite }), vector.contains(where: { $0 != 0 }) else { fatalError("invalid embedding") }
    // A second inference verifies that no random/training behavior was exported.
    let repeated = try model.prediction(from: provider).featureValue(for: "final_emb_1")!.multiArrayValue!
    guard (0..<value.count).allSatisfy({ abs(repeated[$0].doubleValue - vector[$0]) <= 1e-5 }) else { fatalError("non-deterministic inference") }
    vectors[label, default: []].append(vector)
  }
}
let result: [String: Any] = [
  "format": "lumebox.intro.anchors.v1",
  "revision": CommandLine.arguments[3],
  "promptsSha256": SHA256.hash(data: promptData).map { String(format: "%02x", $0) }.joined(),
  "dimension": dimension,
  "vectors": vectors,
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[4]), options: .atomic)
print("Verified eight fixed embeddings (dimension \(dimension)); \(data.count) bytes")
