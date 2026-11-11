#!/usr/bin/env swift
// Read-only Launch Services/UTType probe. Does not register or enable providers.

import Foundation
import UniformTypeIdentifiers

struct ManifestType: Decodable {
    let id: String
    let language: String
    let mode: String
    let extensions: [String]
    let filenames: [String]
    let utis: [String]
}

struct FileResult: Encodable {
    let path: String
    let fileName: String
    let recognizedGroup: String?
    let language: String?
    let mode: String?
    let contentType: String?
    let contentTypeIsDynamic: Bool?
    let preferredExtensionType: String?
    let extensionCandidates: [String]
    let exactWhitelistMatch: Bool
    let status: String
    let error: String?
}

struct ProbeReport: Encodable {
    let schemaVersion = 1
    let inspectedAt: String
    let operatingSystem: String
    let manifest: String
    let registeredTypeCount: Int
    let recognitionSuffixCount: Int
    let inspectedFileCount: Int
    let exactTypeMatchCount: Int
    let limitation: String
    let files: [FileResult]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func classify(_ fileName: String, manifest: [ManifestType]) -> ManifestType? {
    let normalized = fileName.lowercased()
    if let exact = manifest.first(where: { $0.filenames.contains(where: { $0.lowercased() == normalized }) }) {
        return exact
    }
    if normalized.hasPrefix(".env.") {
        return manifest.first { $0.id == "dotenv" }
    }
    if normalized.hasPrefix("dockerfile.") || normalized.hasPrefix("containerfile.") {
        return manifest.first { $0.id == "dockerfile" }
    }
    let suffix = (normalized as NSString).pathExtension
    return manifest.first { $0.extensions.contains(suffix) }
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
var manifestURL = root.appendingPathComponent("Sources/QuicklookCore/Resources/file-types.json")
var outputURL: URL?
var fixtureURL: URL?
var paths: [String] = []
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let argument = args.removeFirst()
    switch argument {
    case "--manifest", "--output", "--create-fixtures":
        guard !args.isEmpty else { fail("Missing value for \(argument)") }
        let url = URL(fileURLWithPath: args.removeFirst()).standardizedFileURL
        if argument == "--manifest" { manifestURL = url }
        if argument == "--output" { outputURL = url }
        if argument == "--create-fixtures" { fixtureURL = url }
    case "--help", "-h":
        print("Usage: swift scripts/probe-routing.swift [--manifest FILE] [--output FILE] [--create-fixtures DIRECTORY] [FILE_OR_DIRECTORY ...]")
        print("Records exact UTI whitelist coverage; does not prove provider execution.")
        exit(0)
    default:
        guard !argument.hasPrefix("--") else { fail("Unknown option: \(argument)") }
        paths.append(argument)
    }
}

let manifest: [ManifestType]
do {
    manifest = try JSONDecoder().decode([ManifestType].self, from: Data(contentsOf: manifestURL))
} catch { fail("Cannot read manifest: \(error.localizedDescription)") }
let whitelist = Set(manifest.flatMap(\.utis))
let suffixes = Set(manifest.flatMap(\.extensions))
let fileManager = FileManager.default
var urls: [URL] = []

if let fixtureURL {
    do {
        try fileManager.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
        for type in manifest {
            for suffix in type.extensions {
                let file = fixtureURL.appendingPathComponent("sample.\(suffix)")
                if !fileManager.fileExists(atPath: file.path) {
                    let text: String
                    switch type.mode {
                    case "markdown": text = "# Quicklook routing sample\n"
                    case "json": text = "{\"routingSample\":true}\n"
                    case "jsonl": text = "{\"record\":1}\n{\"record\":2}\n"
                    default: text = "# Quicklook routing sample\nvalue = 1\n"
                    }
                    try Data(text.utf8).write(to: file)
                }
            }
            for name in type.filenames {
                let file = fixtureURL.appendingPathComponent(name)
                if !fileManager.fileExists(atPath: file.path) {
                    try Data("# Quicklook filename routing sample\n".utf8).write(to: file)
                }
            }
        }
        // Enumerating the directory uses the actual on-disk spelling and avoids
        // counting Makefile/makefile twice on a case-insensitive volume.
        urls.append(contentsOf: try fileManager.contentsOfDirectory(at: fixtureURL, includingPropertiesForKeys: [.isRegularFileKey]).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        })
    } catch { fail("Cannot create routing fixtures: \(error.localizedDescription)") }
}

for path in paths {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { fail("No such file: \(path)") }
    if isDirectory.boolValue {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey]) else { continue }
        for case let file as URL in enumerator {
            if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                urls.append(file)
            }
        }
    } else { urls.append(url) }
}
guard !urls.isEmpty else { fail("Pass files/directories, or --create-fixtures DIRECTORY. Use --help for usage.") }

let preserved = Set(["txt", "text", "html", "htm", "xhtml", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "csv", "svg"])
let files: [FileResult] = Set(urls).sorted { $0.path < $1.path }.map { url in
    let type = classify(url.lastPathComponent, manifest: manifest)
    let suffix = url.pathExtension.lowercased()
    let candidates = suffix.isEmpty ? [] : UTType.types(tag: suffix, tagClass: .filenameExtension, conformingTo: nil).map(\.identifier)
    let preferred = suffix.isEmpty ? nil : UTType(filenameExtension: suffix)?.identifier
    var contentType: UTType?
    var failure: String?
    do { contentType = try url.resourceValues(forKeys: [.contentTypeKey]).contentType }
    catch { failure = error.localizedDescription }
    let match = contentType.map { whitelist.contains($0.identifier) } ?? false
    let status: String
    if failure != nil { status = "metadata-error" }
    else if match { status = "exact-type-covered" }
    else if preserved.contains(suffix), type == nil { status = "system-preserved" }
    else if type != nil { status = "recognized-type-not-routed" }
    else { status = "outside-recognition-matrix" }
    return FileResult(path: url.path, fileName: url.lastPathComponent, recognizedGroup: type?.id, language: type?.language, mode: type?.mode, contentType: contentType?.identifier, contentTypeIsDynamic: contentType?.isDynamic, preferredExtensionType: preferred, extensionCandidates: candidates, exactWhitelistMatch: match, status: status, error: failure)
}

let report = ProbeReport(inspectedAt: ISO8601DateFormatter().string(from: Date()), operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString, manifest: manifestURL.path, registeredTypeCount: whitelist.count, recognitionSuffixCount: suffixes.count, inspectedFileCount: files.count, exactTypeMatchCount: files.filter(\.exactWhitelistMatch).count, limitation: "Exact UTI coverage is registration evidence only. It does not identify the provider chosen by Quick Look or prove rendered output.", files: files)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
do {
    let output = try encoder.encode(report)
    if let outputURL {
        try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try output.write(to: outputURL)
        FileHandle.standardError.write(Data("Wrote \(files.count) files; \(report.exactTypeMatchCount) exact UTI matches to \(outputURL.path)\n".utf8))
    } else {
        FileHandle.standardOutput.write(output)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
} catch { fail("Cannot write routing report: \(error.localizedDescription)") }
