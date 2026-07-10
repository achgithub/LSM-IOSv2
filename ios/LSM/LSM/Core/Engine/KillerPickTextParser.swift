import Foundation

/// One parsed token from a manager-pasted scratchpad string — a fixture
/// number (matching the `.fixtures` share card's numbering), an outcome
/// guess, and — Kill Phase only — a resolved Hit-target player id (from the
/// `.playerKey` card's numbering).
struct ParsedKillerPick {
    let fixtureNumber: Int
    let outcome: FixtureOutcome
    let targetPlayerId: UUID?
}

enum KillerParseError: LocalizedError {
    case empty
    case malformed(String)
    case unknownFixtureNumber(Int)
    case duplicateFixtureNumber(Int)
    case missingHitTarget(fixtureNumber: Int)
    case unknownPlayerNumber(Int)
    case selfTarget(fixtureNumber: Int)
    case duplicateTarget(playerNumber: Int)
    case incomplete(got: Int, expected: Int)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Paste some picks first."
        case .malformed(let text):
            return "Couldn't understand \"\(text)\" — expected e.g. \"1H\" or \"1H2\"."
        case .unknownFixtureNumber(let n):
            return "There's no fixture number \(n) this round."
        case .duplicateFixtureNumber(let n):
            return "Fixture \(n) appears more than once."
        case .missingHitTarget(let n):
            return "Fixture \(n) is missing a Hit target, e.g. \"\(n)H2\"."
        case .unknownPlayerNumber(let n):
            return "There's no player number \(n) in the key."
        case .selfTarget(let n):
            return "Fixture \(n) can't target yourself."
        case .duplicateTarget(let n):
            return "Player number \(n) is targeted more than once — Hits must target different opponents."
        case .incomplete(let got, let expected):
            return "Found \(got) of \(expected) fixtures — check every fixture number is included."
        }
    }
}

/// Parses the manager-pasted texted-shorthand format for Killer picks:
/// `<fixtureNum><H/D/A>` in the Build Phase (e.g. "1H 2A 3D 4H 5H"), or
/// `<fixtureNum><H/D/A><targetPlayerNum>` in the Kill Phase (e.g.
/// "1H2 2A4 3D1 4H3 5H4") — fixture numbers match the `.fixtures` share
/// card, target numbers match the `.playerKey` card. Tolerant of comma/space
/// separation and case. Pure function — no SwiftData access.
enum KillerPickTextParser {
    private static let tokenRegex = try? NSRegularExpression(pattern: #"(\d+)\s*([HDAhda])\s*(\d+)?"#)

    static func parse(
        _ text: String,
        phase: KillerPhase,
        fixtureCount: Int,
        playerNumberToId: [Int: UUID],
        selfPlayerId: UUID
    ) -> Result<[ParsedKillerPick], KillerParseError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let tokenRegex else { return .failure(.malformed(trimmed)) }

        let nsrange = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = tokenRegex.matches(in: trimmed, range: nsrange)
        guard !matches.isEmpty else { return .failure(.malformed(trimmed)) }

        var picks: [ParsedKillerPick] = []
        var seenFixtures: Set<Int> = []
        var seenTargets: Set<Int> = []

        for match in matches {
            guard let fixtureRange = Range(match.range(at: 1), in: trimmed),
                  let outcomeRange = Range(match.range(at: 2), in: trimmed),
                  let fixtureNumber = Int(trimmed[fixtureRange]) else {
                return .failure(.malformed(trimmed))
            }

            let outcome: FixtureOutcome
            switch trimmed[outcomeRange].uppercased() {
            case "H": outcome = .homeWin
            case "D": outcome = .draw
            case "A": outcome = .awayWin
            default: return .failure(.malformed(String(trimmed[outcomeRange])))
            }

            guard (1...fixtureCount).contains(fixtureNumber) else {
                return .failure(.unknownFixtureNumber(fixtureNumber))
            }
            guard !seenFixtures.contains(fixtureNumber) else {
                return .failure(.duplicateFixtureNumber(fixtureNumber))
            }
            seenFixtures.insert(fixtureNumber)

            var targetPlayerId: UUID?
            let targetGroup = match.range(at: 3)
            let targetNumber: Int? = targetGroup.location != NSNotFound
                ? Range(targetGroup, in: trimmed).flatMap { Int(trimmed[$0]) }
                : nil

            if phase == .kill {
                guard let targetNumber else {
                    return .failure(.missingHitTarget(fixtureNumber: fixtureNumber))
                }
                guard let resolvedId = playerNumberToId[targetNumber] else {
                    return .failure(.unknownPlayerNumber(targetNumber))
                }
                guard resolvedId != selfPlayerId else {
                    return .failure(.selfTarget(fixtureNumber: fixtureNumber))
                }
                guard !seenTargets.contains(targetNumber) else {
                    return .failure(.duplicateTarget(playerNumber: targetNumber))
                }
                seenTargets.insert(targetNumber)
                targetPlayerId = resolvedId
            }

            picks.append(ParsedKillerPick(fixtureNumber: fixtureNumber, outcome: outcome, targetPlayerId: targetPlayerId))
        }

        guard picks.count == fixtureCount else {
            return .failure(.incomplete(got: picks.count, expected: fixtureCount))
        }

        return .success(picks)
    }
}
