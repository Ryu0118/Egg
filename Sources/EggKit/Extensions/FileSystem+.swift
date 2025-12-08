import FileSystem
import Path
import Yams

extension FileSysteming {
    func writeAsYAML(
        _ item: some Encodable,
        at path: Path.AbsolutePath,
        encoder: YAMLEncoder,
        options: Set<WriteJSONOptions> = []
    ) async throws {
        let yaml = try encoder.encode(item)
        if options.contains(.overwrite), try await exists(path) {
            try await remove(path)
        }
        try await writeText(yaml, at: path)
    }
}
