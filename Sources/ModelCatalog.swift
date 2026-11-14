import Foundation

/// A model the app can download and run, with what it needs from the phone.
struct ModelSpec: Sendable {
    /// The Apple-hosted asset pack it ships in.
    let assetPackID: String
    /// The model's name as people see it.
    let displayName: String
    /// The Hugging Face repository and revision the pack is built from (scripts/release-model-pack.sh).
    let hubID: String
    let revision: String
    let license: String
    let licenseURL: URL
    let downloadBytes: Int64
    let weightsBytes: Int64
    /// The smallest iPhone it has been measured on. Smaller ones aren't offered it, whatever they report.
    let minDeviceBytes: Int64
    /// End-of-turn tokens the tokenizer's config doesn't list.
    let extraEOSTokens: Set<String>
    /// Extra values for the model's chat template.
    let templateContext: [String: any Sendable]

    var budget: MemoryBudget { MemoryBudget(weightsBytes: weightsBytes) }
}

/// The models the app knows, and which one a given iPhone gets.
enum ModelCatalog {
    /// Qwen 3.5 4B, 4-bit. Apache 2.0, so it can ship in a paid app with the license text included.
    /// Measured on an iPhone 17 (8 GB, app limit 6144 MiB): see docs/on-device-model-comparison.md.
    static let qwen35_4B = ModelSpec(
        assetPackID: "answers",
        displayName: "Qwen 3.5 4B",
        hubID: "mlx-community/Qwen3.5-4B-MLX-4bit",
        revision: "32f3e8ecf65426fc3306969496342d504bfa13f3",
        license: "Apache 2.0",
        licenseURL: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!,
        downloadBytes: 2_261_254_682,
        weightsBytes: 2_394_053_774,
        minDeviceBytes: 7_000_000_000,  // "8 GB" iPhones report about 7.7 GB
        extraEOSTokens: ["<|im_end|>"],
        // Qwen 3.x thinks out loud first unless the chat template is told not to.
        templateContext: ["enable_thinking": false])

    /// Best first. A smaller model for 6 GB iPhones would go after it, once one answers safely.
    static let all = [qwen35_4B]

    /// The best model this iPhone can run, from its memory and the limit iOS gives the app.
    /// Nil when none fits; Apple's model answers then.
    static func best(deviceBytes: Int64, appLimitBytes: Int64?) -> ModelSpec? {
        guard let appLimitBytes else { return nil }  // the simulator: no limit, and no GPU MLX can use
        return all.first { deviceBytes >= $0.minDeviceBytes && appLimitBytes >= $0.budget.neededBytes }
    }
}
