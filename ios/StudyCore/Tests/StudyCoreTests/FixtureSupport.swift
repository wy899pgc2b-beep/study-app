import Foundation
import XCTest

@testable import StudyCore

// 試作品(JS)から書き出した突き合わせ用のデータ(Fixtures/*.json)を読み、Swift の結果と比べるための道具。
// データは prototype/tools/export-parity-fixtures.mjs で作る。

/// JSON の値。数と真偽は数として扱う(試作品の 0/1 と true/false を同じとみなす)
indirect enum JSONValue: Decodable, CustomStringConvertible {
  case null
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let d = try? c.decode(Double.self) {
      self = .number(d)
    } else if let b = try? c.decode(Bool.self) {
      self = .number(b ? 1 : 0)
    } else if let s = try? c.decode(String.self) {
      self = .string(s)
    } else if let a = try? c.decode([JSONValue].self) {
      self = .array(a)
    } else {
      self = .object(try c.decode([String: JSONValue].self))
    }
  }

  /// null と同じとみなす値(試作品の JSON では、NaN・Infinity は null になる)
  var isNullish: Bool {
    switch self {
    case .null: return true
    case .string(let s): return s == "NaN" || s == "Infinity" || s == "-Infinity"
    default: return false
    }
  }

  var description: String {
    switch self {
    case .null: return "null"
    case .number(let d): return "\(d)"
    case .string(let s): return "\"\(s)\""
    case .array(let a): return "[\(a.count) items]"
    case .object(let o): return "{\(o.keys.sorted().prefix(4).joined(separator: ","))…}"
    }
  }
}

let fixturesDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

func loadFixture<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
  let data = try Data(contentsOf: fixturesDir.appendingPathComponent("\(name).json"))
  return try JSONDecoder().decode(T.self, from: data)
}

private let encoder: JSONEncoder = {
  let e = JSONEncoder()
  e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
  return e
}()

/// Swift の値を JSON の値にする(nil は null)
func toJSON<T: Encodable>(_ value: T?) throws -> JSONValue {
  guard let value else { return .null }
  return try JSONDecoder().decode(JSONValue.self, from: encoder.encode(value))
}

/// actual(Swift)と expected(試作品)を比べ、違うところを path つきで mismatches に足す。
/// 数は有効数字 10 桁に丸めて保存しているので、相対 1e-7 の誤差を許す。どちらかにしかない項目は null とみなす。
func diffJSON(_ actual: JSONValue?, _ expected: JSONValue?, _ path: String, _ mismatches: inout [String]) {
  let a = actual ?? .null
  let e = expected ?? .null
  if a.isNullish && e.isNullish { return }
  switch (a, e) {
  case (.number(let x), .number(let y)):
    if abs(x - y) > 1e-7 + 1e-7 * abs(y) { mismatches.append("\(path): swift \(x) / js \(y)") }
  case (.string(let x), .string(let y)):
    if x != y { mismatches.append("\(path): swift \"\(x)\" / js \"\(y)\"") }
  case (.array(let x), .array(let y)):
    if x.count != y.count {
      mismatches.append("\(path): swift \(x.count) items / js \(y.count) items")
      return
    }
    for i in 0..<x.count { diffJSON(x[i], y[i], "\(path)[\(i)]", &mismatches) }
  case (.object(let x), .object(let y)):
    for k in Set(x.keys).union(y.keys).sorted() { diffJSON(x[k], y[k], "\(path).\(k)", &mismatches) }
  default:
    mismatches.append("\(path): swift \(a) / js \(e)")
  }
}

// MARK: - analyzer.json(試作品のテストが Analyzer に入れた特徴量と、そのときの判定の結果)

struct AnalyzerFixture: Decodable {
  let appVersion: String
  let sessions: [AnalyzerSession]
}

struct AnalyzerSession: Decodable {
  struct Options: Decodable {
    let autoAway: Bool
    let setup: SetupStyle
  }

  let cfg: AnalysisConfig
  let options: Options
  let ops: [AnalyzerOp]

  var frames: [Features] {
    ops.compactMap { op -> Features? in
      if case .frame(let f, _, _) = op { return f }
      return nil
    }
  }

  var outputs: [(f: Features, out: OutputLite)] {
    ops.compactMap { op -> (f: Features, out: OutputLite)? in
      if case .frame(let f, _, let o) = op { return (f, o) }
      return nil
    }
  }
}

/// 判定の結果のうち、1 分ごとの集計に使う部分
struct OutputLite: Decodable {
  let state: StudyState
  let away: Bool
  let events: [AnalysisEvent]
}

enum AnalyzerOp: Decodable {
  case calibration(Calibration?)
  case frame(Features, JSONValue, OutputLite)

  enum CodingKeys: String, CodingKey { case cal, f, out }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if c.contains(.cal) {
      self = .calibration(try c.decodeIfPresent(Calibration.self, forKey: .cal))
    } else {
      self = .frame(
        try c.decode(Features.self, forKey: .f), try c.decode(JSONValue.self, forKey: .out), try c.decode(OutputLite.self, forKey: .out))
    }
  }
}

// MARK: - features.json(検出結果 → 特徴量)

struct FeaturesFixture: Decodable {
  struct Case: Decodable {
    let frame: Frame
    let features: JSONValue
  }

  let appVersion: String
  let cfg: JSONValue
  let cases: [Case]
}

// MARK: - misc.json(キャリブレーション・位置合わせ・1 分ごとの集計・学習スタイル)

struct MiscFixture: Decodable {
  struct CalOpts: Decodable {
    let measuredEyeDeskCm: Double
    let tiltDeg: Double
  }

  struct CalibrationCase: Decodable {
    let session: Int
    let from: Int
    let to: Int
    let opts: CalOpts
    let cal: JSONValue
    let closedFrom: Int
    let closedTo: Int
    let closedRef: JSONValue
    let eyeSignal: String?
  }

  struct FramingCase: Decodable {
    let session: Int
    let frame: Int
    let setup: SetupStyle
    let ok: Bool
    let codes: [String]
  }

  struct RecorderCase: Decodable {
    let session: Int
    let autoAway: Bool
    let startT: Double
    let summary: JSONValue
    let minutes: JSONValue
  }

  struct ScoreCase: Decodable {
    struct Minute: Decodable {
      let secs: MinuteSecs
      let habits: Int
      let interruptions: Int
    }

    let minute: Minute
    let autoAway: Bool
    let score: Int?
  }

  struct StyleCase: Decodable {
    let work: Double
    let think: Double
    let scores: [Int?]
    let style: JSONValue
  }

  let appVersion: String
  let calibration: [CalibrationCase]
  let framing: [FramingCase]
  let recorder: [RecorderCase]
  let scoreMinute: [ScoreCase]
  let learningStyle: [StyleCase]
}

/// 違いをまとめて報告する(多すぎると読めないので先頭だけ)
func reportMismatches(_ mismatches: [String], _ what: String, file: StaticString = #filePath, line: UInt = #line) {
  if mismatches.isEmpty { return }
  let head = mismatches.prefix(40).joined(separator: "\n")
  XCTFail("\(what): \(mismatches.count) 件の違い\n\(head)", file: file, line: line)
}
