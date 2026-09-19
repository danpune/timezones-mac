// Signs a release zip so the app's updater can tell it really came from the owner. `./build.sh release` runs it.
//   swift Tools/sign.swift --new-key     once: makes the private key and prints the public half for Updater.swift
//   swift Tools/sign.swift FILE.zip      writes FILE.zip.sig
// The private key stays at ~/.config/timezones-mac/update.key, never in the repo. Back it up: without it,
// new versions can't be signed and everyone would have to download the next one by hand.
import CryptoKit
import Foundation

let keyFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/timezones-mac/update.key")
let arg = CommandLine.arguments.dropFirst().first ?? ""

if arg == "--new-key" {
    guard !FileManager.default.fileExists(atPath: keyFile.path) else { print("A key already exists at \(keyFile.path)"); exit(1) }
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(at: keyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: keyFile.path, contents: Data(key.rawRepresentation.base64EncodedString().utf8),
                                   attributes: [.posixPermissions: 0o600])
    print("Public key for Updater.swift:", key.publicKey.rawRepresentation.base64EncodedString())
} else if !arg.isEmpty {
    guard let text = try? String(contentsOf: keyFile, encoding: .utf8), let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { FileHandle.standardError.write(Data("No signing key at \(keyFile.path)\n".utf8)); exit(1) }
    let zip = try Data(contentsOf: URL(fileURLWithPath: arg))
    try key.signature(for: zip).write(to: URL(fileURLWithPath: arg + ".sig"))
    print("Signed \(arg), public key \(key.publicKey.rawRepresentation.base64EncodedString())")
} else {
    print("Usage: swift Tools/sign.swift --new-key | FILE.zip"); exit(1)
}
