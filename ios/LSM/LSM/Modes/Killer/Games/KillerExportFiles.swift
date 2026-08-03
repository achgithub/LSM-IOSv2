import Foundation

/// Writes a Killer game's CSV export to two temp files for the share
/// sheet — mirrors LMS's `GameExportFiles`.
enum KillerExportFiles {
    enum ExportError: Error { case writeFailed }

    static func write(for game: Game, data: LeagueData) throws -> [URL] {
        let illegalCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let safeName = game.name
            .components(separatedBy: illegalCharacters)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let base = safeName.isEmpty ? "Game" : safeName

        let metadataURL = try write(KillerExportCSV.metadataCSV(for: game), named: "\(base) - metadata.csv")
        let predictionsURL = try write(KillerExportCSV.predictionsCSV(for: game, data: data), named: "\(base) - predictions.csv")
        return [metadataURL, predictionsURL]
    }

    private static func write(_ contents: String, named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.writeFailed
        }
        return url
    }
}
