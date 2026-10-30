import Foundation
struct RenamePair { var original: URL; var renamed: URL }
enum RenameService {
 static func plan(_ urls: [URL], options o: Options) throws -> [RenamePair] {
  guard o.start >= 0, (1...12).contains(o.digits) else { throw WorkError("编号起点须非负，位数须为 1–12。") }
  var result: [RenamePair] = []; var names = Set<String>()
  let sources = Set(urls.map { $0.standardizedFileURL.path })
  for (index,url) in urls.enumerated() {
   var stem = o.base.isEmpty ? url.deletingPathExtension().lastPathComponent : o.base+"_"+String(format:"%0*d",o.digits,o.start+index)
   if !o.find.isEmpty { stem = stem.replacingOccurrences(of:o.find,with:o.replace) }
   let name = o.prefix+stem+o.suffix
   guard !name.isEmpty, !name.contains("/"), !name.contains(":"), !name.contains("\0"), name != ".", name != ".." else { throw WorkError("名称含有无效字符。") }
   let target = url.deletingLastPathComponent().appendingPathComponent(name).appendingPathExtension(url.pathExtension)
   let key = target.path.precomposedStringWithCanonicalMapping.lowercased()
   guard names.insert(key).inserted else { throw WorkError("多个文件将得到同一个名称：\(target.lastPathComponent)") }
   if FileManager.default.fileExists(atPath:target.path) && !sources.contains(target.standardizedFileURL.path) { throw WorkError("目标名称已存在：\(target.lastPathComponent)") }
   result.append(RenamePair(original:url,renamed:target))
  }
  return result
 }
 static func apply(_ plan: [RenamePair]) throws {
  let fm = FileManager.default
  // Stage all files first, allowing cycles and case-only renames without overwriting.
  var staged: [(RenamePair,URL)] = []; var completed = Set<Int>()
  do {
   for pair in plan {
    let temp = pair.original.deletingLastPathComponent().appendingPathComponent(".material-rename-\(UUID().uuidString)")
    try fm.moveItem(at:pair.original,to:temp); staged.append((pair,temp))
   }
   for (i,entry) in staged.enumerated() { guard !fm.fileExists(atPath:entry.0.renamed.path) else { throw WorkError("目标文件在执行期间出现，已停止：\(entry.0.renamed.lastPathComponent)") }; try fm.moveItem(at:entry.1,to:entry.0.renamed); completed.insert(i) }
  } catch {
   var rollbackErrors: [String] = []
   for i in completed { do { try fm.moveItem(at:staged[i].0.renamed,to:staged[i].1) } catch { rollbackErrors.append(staged[i].0.renamed.path) } }
   for entry in staged where fm.fileExists(atPath:entry.1.path) { do { try fm.moveItem(at:entry.1,to:entry.0.original) } catch { rollbackErrors.append(entry.1.path) } }
   if !rollbackErrors.isEmpty { throw WorkError("操作失败且部分文件未能恢复，请保留以下路径并手动恢复：\n"+rollbackErrors.joined(separator:"\n")) }; throw error
  }
 }
}
