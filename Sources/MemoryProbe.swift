import Foundation
import os

/// How much memory the app is using and how much more iOS will allow before it stops the app.
enum MemoryProbe {
    /// The app's memory as iOS counts it against the limit (phys_footprint).
    static var footprintBytes: Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return r == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    /// What the app can still allocate before iOS stops it. Zero in the simulator, which has no limit.
    static var availableBytes: Int64 {
        #if os(macOS)
        deviceBytes  // the Mac tools (ScoutTools): macOS sets no per-app limit
        #else
        Int64(os_proc_available_memory())
        #endif
    }
    static var deviceBytes: Int64 { Int64(ProcessInfo.processInfo.physicalMemory) }
    /// The most memory iOS lets this app hold: what it uses now plus what it may still take. Nil in the simulator.
    static var ceilingBytes: Int64? {
        let available = availableBytes
        return available > 0 ? footprintBytes + available : nil
    }

    static var footprintGB: Double { Double(footprintBytes) / 1e9 }
    static var availableGB: Double { Double(availableBytes) / 1e9 }
    static var deviceGB: Double { Double(deviceBytes) / 1e9 }

    /// One line for the log: the device's memory, this app's limit and how much of it is in use.
    static func report(_ moment: String) -> String {
        let mib = { (bytes: Int64) in "\(bytes / 1_048_576) MiB" }
        let ceiling = ceilingBytes.map(mib) ?? "none (simulator)"
        return "memory at \(moment): device \(mib(deviceBytes)), app limit \(ceiling), "
            + "in use \(mib(footprintBytes)), available \(mib(availableBytes))"
    }
}

/// Decides whether a model can be loaded without iOS stopping the app for using too much memory.
struct MemoryBudget: Sendable, Equatable {
    /// The weights, which MLX holds in memory whole.
    var weightsBytes: Int64
    /// What answering adds on top: the key-value cache, the working buffers and MLX's buffer cache.
    var workingBytes: Int64 = 900_000_000
    /// Left free for the rest of the app while the model answers.
    var reserveBytes: Int64 = 300_000_000

    var neededBytes: Int64 { weightsBytes + workingBytes + reserveBytes }

    /// Throws when `availableBytes` (os_proc_available_memory) is too little to load and answer.
    func check(availableBytes: Int64) throws {
        guard availableBytes >= neededBytes else {
            throw LLMError.notEnoughMemory(neededBytes: neededBytes, availableBytes: availableBytes)
        }
    }
}

/// The log for everything about running a model on the phone: memory, load time, speed, heat.
/// Debug builds also print, so `devicectl device process launch --console` shows it.
enum LLMLog {
    private static let logger = Logger(subsystem: "com.collinbrowse.backcountryai", category: "llm")

    static func note(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        #if DEBUG
        print("[llm] \(message)")
        #endif
    }
}
