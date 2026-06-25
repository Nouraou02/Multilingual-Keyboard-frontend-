import Foundation
import MLX
import MLXNN
import MLXLLM
import MLXLMCommon

public enum KeyboardLanguageExpert: String, Sendable {
    case english = "EN"
    case french = "FR"
    case chinese = "ZH"
}

public struct KeyboardPrediction: Sendable {
    public let suggestions: [String]
    public let language: KeyboardLanguageExpert
    public let confidence: Float
}

public actor OnDeviceKeyboardEngine {

    public static let shared = OnDeviceKeyboardEngine()

    private var modelContainer: ModelContainer?

    private var activeExpert: KeyboardLanguageExpert = .english

    // Router weights
    private var routerWeight: MLXArray?
    private var routerBias: MLXArray?
    
    // Adapter tracking properties
    private var frenchAdapterURL: URL?
    private var chineseAdapterURL: URL?

    private init() {}

    // MARK: - Load Model

    // MARK: - Bulletproof Folder-Reference Path Loader

    public func loadModel(
            tokenizerLoader: any TokenizerLoader
        ) async throws {
            
            let bundleURL = Bundle.main.bundleURL
            let fm = FileManager.default
            
            print("====================================================")
            print("🚀 INITIALIZING MULTILINGUAL INFERENCE PIPELINE")
            print("====================================================")
            
            // 1. Target the absolute subfolder paths inside the compiled bundle
            let baseModelURL = bundleURL.appendingPathComponent("Qwen3-1.7B")
            let frURL = bundleURL.appendingPathComponent("qwen_fr_4bit")
            let zhURL = bundleURL.appendingPathComponent("qwen_zh_4bit")
            
            self.frenchAdapterURL = frURL
            self.chineseAdapterURL = zhURL
            
            // 2. Validate that the base folder structure exists on disk
            guard fm.fileExists(atPath: baseModelURL.path) else {
                throw NSError(
                    domain: "OnDeviceKeyboardEngine",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "❌ File System Error: Base model directory 'Qwen3-1.7B' was not copied into the bundle. Current target path:\n\(baseModelURL.path)"]
                )
            }
            
            print("📂 Base Model Isolated Path: \(baseModelURL.path)")
            print("📂 French Adapter Isolated Path: \(frURL.path)")
            print("📂 Chinese Adapter Isolated Path: \(zhURL.path)")
            print("⏳ Materializing model weights into active container allocation...")
            
            // 3. Load the isolated base model directory into MLX
            self.modelContainer = try await LLMModelFactory.shared.loadContainer(
                from: baseModelURL,
                using: tokenizerLoader
            )
            
            print("================ 🎉 ENGINE STABLE ================")
        }
    // MARK: - Load Router

    public func setRouter(
        weight: MLXArray,
        bias: MLXArray
    ) {
        self.routerWeight = weight
        self.routerBias = bias
    }

    // MARK: - Main Prediction Entry

    public func predict(
        text: String
    ) async throws -> KeyboardPrediction {

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return KeyboardPrediction(
                suggestions: [],
                language: .english,
                confidence: 1.0
            )
        }

        guard let modelContainer else {
            throw NSError(
                domain: "OnDeviceKeyboardEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]
            )
        }

        let encodedTokens = try await modelContainer.perform { context in
            try context.tokenizer.encode(text: text)
        }

        let routerResult = try await detectLanguage(
            text: text,
            tokens: encodedTokens
        )

        if routerResult.language != activeExpert {
            try await switchExpert(to: routerResult.language)
        }

        let suggestions = try await nextWordSuggestions(
            text: text,
            tokens: encodedTokens
        )

        return KeyboardPrediction(
            suggestions: suggestions,
            language: routerResult.language,
            confidence: routerResult.confidence
        )
    }

    // MARK: - Router

    private func detectLanguage(
        text: String,
        tokens: [Int]
    ) async throws -> (
        language: KeyboardLanguageExpert,
        confidence: Float
    ) {

        guard let modelContainer else {
            return (.english, 1.0)
        }

        guard let routerWeight,
              let routerBias else {
            return (.english, 1.0)
        }

        return try await modelContainer.perform { context in

            let inputTensor = MLXArray(tokens).reshaped([1, tokens.count])

            let cache = context.model.newCache(parameters: nil)

            let output = context.model(
                inputTensor,
                cache: cache
            )

            eval(output)

            let logits = output

            let lastTokenLogits = logits[0, logits.shape[1] - 1]

            let routerLogits =
                matmul(
                    lastTokenLogits.reshaped([1, lastTokenLogits.count]),
                    routerWeight.transposed()
                ) + routerBias

            let probs = softmax(routerLogits, axis: -1)

            eval(probs)

            let values = probs.asArray(Float.self)

            guard values.count >= 3 else {
                return (.english, 1.0)
            }

            let confidence = values.max() ?? 1.0
            let index = values.firstIndex(of: confidence) ?? 0

            var language: KeyboardLanguageExpert

            switch index {
            case 1:
                language = .french

            case 2:
                language = .chinese

            default:
                language = .english
            }

            if language == .chinese {

                let containsChinese =
                    text.unicodeScalars.contains {
                        $0.value >= 0x4E00 &&
                        $0.value <= 0x9FFF
                    }

                if !containsChinese {
                    language = .english
                }
            }

            return (language, confidence)
        }
    }

    // MARK: - Suggestions

    private func nextWordSuggestions(
        text: String,
        tokens: [Int]
    ) async throws -> [String] {

        guard let modelContainer else {
            return []
        }

        let isAtSpace = text.hasSuffix(" ")

        let fragment: String = {
            guard !isAtSpace else { return "" }

            return text
                .split(separator: " ")
                .last?
                .lowercased() ?? ""
        }()

        return try await modelContainer.perform { context in

            let inputTensor = MLXArray(tokens)
                .reshaped([1, tokens.count])

            let cache = context.model.newCache(parameters: nil)

            let logits = context.model(
                inputTensor,
                cache: cache
            )

            eval(logits)

            let lastPosition = logits.shape[1] - 1

            let nextTokenLogits =
                logits[0, lastPosition]

            let sorted = MLX.argSort(nextTokenLogits, axis:-1)

            eval(sorted)

            let tokenIds =
                Array(sorted.asArray(Int.self).suffix(100).reversed())

            var predictions: [String] = []
            var seen = Set<String>()

            for tokenId in tokenIds {

                let decoded = try context.tokenizer.decode(
                    tokenIds: [tokenId]
                )

                let trimmed =
                    decoded.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

                if trimmed.isEmpty {
                    continue
                }

                if containsChinese(trimmed) {

                    var candidate = trimmed

                    if candidate.hasPrefix(text) {

                        candidate.removeFirst(text.count)

                    } else if !fragment.isEmpty &&
                              candidate.hasPrefix(fragment) {

                        candidate.removeFirst(fragment.count)
                    }

                    candidate =
                        candidate.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )

                    if !candidate.isEmpty &&
                        !seen.contains(candidate) {

                        predictions.append(candidate)
                        seen.insert(candidate)
                    }

                } else {

                    let lower = trimmed.lowercased()

                    if seen.contains(lower) {
                        continue
                    }

                    if !isAtSpace &&
                        !fragment.isEmpty {

                        if lower.hasPrefix(fragment) &&
                            lower != fragment {

                            predictions.append(trimmed)
                            seen.insert(lower)

                        } else {

                            let combined =
                                fragment + lower

                            if !seen.contains(combined) {

                                predictions.append(combined)
                                seen.insert(combined)
                            }
                        }

                    } else {

                        predictions.append(trimmed)
                        seen.insert(lower)
                    }
                }

                if predictions.count >= 3 {
                    break
                }
            }

            return predictions
        }
    }

    // MARK: - Adapter Switch

    private func switchExpert(
        to expert: KeyboardLanguageExpert
    ) async throws {

        activeExpert = expert

        switch expert {

        case .english:
            print("Using Base English")

        case .french:
            print("Using French LoRA")

        case .chinese:
            print("Using Chinese LoRA")
        }
    }

    // MARK: - Helpers

    nonisolated private func containsChinese(
        _ text: String
    ) -> Bool {

        text.unicodeScalars.contains {
            $0.value >= 0x4E00 &&
            $0.value <= 0x9FFF
        }
    }
}
