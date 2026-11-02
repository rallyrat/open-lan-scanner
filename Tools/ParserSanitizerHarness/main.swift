import Foundation
import OpenLANScannerCore
import OLSAsanPositiveControl

#if canImport(Darwin)
import Darwin
#endif

/// Dedicated executable for AddressSanitizer validation of extracted parsers.
/// Not part of the shipping app. Run via `Scripts/run-asan-harness.sh`.

enum HarnessError: Error {
    case unknownCommand(String)
}

@main
struct ParserSanitizerHarness {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty || args.contains("--help") || args.contains("-h") {
            printUsage()
            return
        }

        if args.contains("--positive-control") {
            // Must abort under ASan. Never call from production code paths.
            ols_asan_positive_control()
            // If we reach here, instrumentation is NOT active.
            fputs("error: positive-control completed without ASan abort — instrumentation inactive\n", stderr)
            exit(2)
        }

        var seedRouting: UInt64 = 0xC0FFEE_F00D_2026
        var seedICMP: UInt64 = 0x1CE_B00B5_2026
        var iterations = 200
        var maxSize = 4096
        var runRouting = false
        var runICMP = false

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--fuzz-routing":
                runRouting = true
            case "--fuzz-icmp":
                runICMP = true
            case "--all-fuzz":
                runRouting = true
                runICMP = true
            case "--seed-routing":
                i += 1
                guard i < args.count, let v = parseUInt64(args[i]) else {
                    throw HarnessError.unknownCommand(a)
                }
                seedRouting = v
            case "--seed-icmp":
                i += 1
                guard i < args.count, let v = parseUInt64(args[i]) else {
                    throw HarnessError.unknownCommand(a)
                }
                seedICMP = v
            case "--iterations":
                i += 1
                guard i < args.count, let v = Int(args[i]), v > 0 else {
                    throw HarnessError.unknownCommand(a)
                }
                iterations = min(v, 5_000)
            case "--max-size":
                i += 1
                guard i < args.count, let v = Int(args[i]), v > 0 else {
                    throw HarnessError.unknownCommand(a)
                }
                maxSize = min(v, 16_384)
            default:
                throw HarnessError.unknownCommand(a)
            }
            i += 1
        }

        if !runRouting && !runICMP {
            fputs("error: specify --fuzz-routing, --fuzz-icmp, or --all-fuzz\n", stderr)
            exit(1)
        }

        if runRouting {
            let count = fuzzRouting(seed: seedRouting, iterations: iterations, maxSize: maxSize)
            print("routing-fuzz-ok iterations=\(count) seed=0x\(String(seedRouting, radix: 16)) maxSize=\(maxSize)")
        }
        if runICMP {
            let count = fuzzICMP(seed: seedICMP, iterations: iterations, maxSize: maxSize)
            print("icmp-fuzz-ok iterations=\(count) seed=0x\(String(seedICMP, radix: 16)) maxSize=\(maxSize)")
        }
    }

    static func parseUInt64(_ text: String) -> UInt64? {
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            return UInt64(text.dropFirst(2), radix: 16)
        }
        return UInt64(text)
    }

    static func printUsage() {
        print(
            """
            OLSParserSanitizerHarness — AddressSanitizer parser harness (not shipped)

            Usage:
              OLSParserSanitizerHarness --positive-control
              OLSParserSanitizerHarness --all-fuzz [--iterations N] [--max-size N]
              OLSParserSanitizerHarness --fuzz-routing [--seed-routing 0x...]
              OLSParserSanitizerHarness --fuzz-icmp [--seed-icmp 0x...]

            Prefer Scripts/run-asan-harness.sh which builds with -sanitize=address
            and verifies the positive-control abort before running fuzz corpora.
            """
        )
    }

    // MARK: - Fuzz corpora (deterministic; mirrors XCTest seeds)

    struct SeededRNG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return state &* 0x2545F4914F6CDD1D
        }
        mutating func byte() -> UInt8 { UInt8(truncatingIfNeeded: next()) }
        mutating func int(in range: ClosedRange<Int>) -> Int {
            let span = UInt64(range.upperBound - range.lowerBound) &+ 1
            return range.lowerBound + Int(next() % span)
        }
    }

    static func fuzzRouting(seed: UInt64, iterations: Int, maxSize: Int) -> Int {
        var rng = SeededRNG(state: seed)
        let sizes = [0, 1, 2, 3, 7, 8, 15, 16, 32, 64, 128, 256, 1024, maxSize]
        var ran = 0
        for size in sizes where size <= maxSize {
            for _ in 0..<iterations {
                var buffer = [UInt8](repeating: 0, count: size)
                for i in 0..<size { buffer[i] = rng.byte() }
                if size >= 2 {
                    buffer[0] = 0xFF
                    buffer[1] = 0xFF
                }
                _ = RoutingTableParser.parseARPEntries(from: buffer)
                ran += 1
            }
        }
        // Explicit truncated / empty cases
        _ = RoutingTableParser.parseARPEntries(from: [])
        _ = RoutingTableParser.parseARPEntries(from: [0, 0, 0, 0])
        return ran
    }

    static func fuzzICMP(seed: UInt64, iterations: Int, maxSize: Int) -> Int {
        var rng = SeededRNG(state: seed)
        var ran = 0
        for size in [0, 1, 7, 8, 9, 20, 21, 64, 128, maxSize] where size <= maxSize {
            for _ in 0..<iterations {
                var buf = [UInt8](repeating: 0, count: size)
                for i in 0..<size { buf[i] = rng.byte() }
                _ = ICMPPacketCodec.parseHeader(from: buf, offset: rng.int(in: 0...max(0, size)))
                _ = ICMPPacketCodec.isMatchingEchoReply(
                    buf,
                    expectedIdentifier: UInt16(truncatingIfNeeded: rng.next()),
                    expectedSequence: UInt16(truncatingIfNeeded: rng.next())
                )
                _ = ICMPPacketCodec.checksum(buf)
                ran += 1
            }
        }
        // Valid round-trip under sanitizer
        let req = ICMPPacketCodec.buildEchoRequest(identifier: 0xABCD, sequence: 7)
        _ = ICMPPacketCodec.checksum(req)
        return ran
    }
}
