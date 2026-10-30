import Foundation
final class ProcessRunner: @unchecked Sendable {
 private let lock = NSLock(); private var process: Process?; private var cancelled = false
 func cancel() { lock.lock(); cancelled = true; let p = process; lock.unlock(); if p?.isRunning == true { p?.terminate() } }
 func reset() { lock.lock(); cancelled = false; lock.unlock() }
 var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
 func run(_ name: String, _ args: [String], progress: ((Double)->Void)? = nil, duration: Double = 0, lineHandler: ((String)->Void)? = nil) throws -> Data {
  if isCancelled { throw CancellationError() }
  let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(name)")
  guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw WorkError("缺少内置 \(name)，请重新构建完整应用。") }
  let p = Process(); p.executableURL = executable; p.arguments = args
  let out = Pipe(); let err = Pipe(); p.standardOutput = out; p.standardError = err
  let logURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  FileManager.default.createFile(atPath: logURL.path, contents: nil)
  let log = try FileHandle(forWritingTo: logURL); p.standardError = log
  defer { try? log.close(); try? FileManager.default.removeItem(at: logURL) }
  lock.lock(); process = p; let stop = cancelled; lock.unlock(); if stop { throw CancellationError() }
  try p.run(); if isCancelled { p.terminate() }; var result = Data(); var line = ""
  while true {
   let data = out.fileHandleForReading.availableData; if data.isEmpty { break }
   if progress == nil && lineHandler == nil { result.append(data) } else {
    line += String(decoding: data, as: UTF8.self)
    while let end = line.firstIndex(of: "\n") { let s = String(line[..<end]); line.removeSubrange(...end); lineHandler?(s); if s.hasPrefix("out_time_us="), let t = Double(s.dropFirst(12)), duration > 0 { progress?(min(0.99,t / 1_000_000 / duration)) } }
   }
  }
  if !line.isEmpty { lineHandler?(line) }
  p.waitUntilExit(); lock.lock(); process = nil; lock.unlock()
  if isCancelled { throw CancellationError() }
  if p.terminationStatus != 0 { let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""; throw WorkError("处理失败：\(text.suffix(1400))") }; return result
 }
}
