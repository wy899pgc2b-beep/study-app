// 判定のしきい値(js/config.js の DEFAULTS)から、iPhone アプリの StudyCore の設定(Config.swift)を作る。
// しきい値は試作品で調整してきたので、Swift 側で手で書き写さず、このスクリプトで同じ値にそろえる。
// 使い方:node tools/gen-swift-config.mjs(prototype/ で実行)
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { APP_VERSION, DEFAULTS, SETUP_TILT_DEG, TILT_RANGE_DEG } from '../js/config.js';

const here = dirname(fileURLToPath(import.meta.url));
const OUT = join(here, '../../ios/StudyCore/Sources/StudyCore/Config.swift');

const entries = Object.entries(DEFAULTS);
const typeOf = (v) => (typeof v === 'boolean' ? 'Bool' : 'Double');
const lit = (v) => (typeof v === 'boolean' ? String(v) : Number.isInteger(v) ? `${v}` : `${v}`);

const lines = [];
lines.push('// このファイルは prototype/tools/gen-swift-config.mjs で prototype/js/config.js から作る。手で書き換えない。');
lines.push(`// もとにした試作品の版:${APP_VERSION}`);
lines.push('');
lines.push('import Foundation');
lines.push('');
lines.push('/// 判定のしきい値(設計書 4 章)。値の意味と調整の経緯は prototype/js/config.js のコメントを参照。');
lines.push('public struct AnalysisConfig: Codable, Equatable, Sendable {');
lines.push(`  public static let prototypeVersion = "${APP_VERSION}"`);
lines.push('');
for (const [k, v] of entries) lines.push(`  public var ${k}: ${typeOf(v)} = ${lit(v)}`);
lines.push('');
lines.push('  public init() {}');
lines.push('');
lines.push('  // 足りない項目は既定値のままにする(試作品のテストは一部の値だけを変えた設定を使う)');
lines.push('  public init(from decoder: Decoder) throws {');
lines.push('    let c = try decoder.container(keyedBy: CodingKeys.self)');
for (const [k, v] of entries) lines.push(`    if let x = try c.decodeIfPresent(${typeOf(v)}.self, forKey: .${k}) { ${k} = x }`);
lines.push('  }');
lines.push('}');
lines.push('');
lines.push('/// 置き方ごとのカメラの上向きの傾き(度)。センサーが読めないときに使う。');
lines.push('public enum SetupStyle: String, Codable, Sendable, CaseIterable {');
for (const k of Object.keys(SETUP_TILT_DEG)) lines.push(`  case ${k}`);
lines.push('');
lines.push('  public var defaultTiltDeg: Double {');
lines.push('    switch self {');
for (const [k, v] of Object.entries(SETUP_TILT_DEG)) lines.push(`    case .${k}: return ${lit(v)}`);
lines.push('    }');
lines.push('  }');
lines.push('');
lines.push('  /// 位置合わせで求める傾きの範囲(度)。範囲のない置き方は nil。');
lines.push('  public var tiltRangeDeg: ClosedRange<Double>? {');
lines.push('    switch self {');
for (const k of Object.keys(SETUP_TILT_DEG)) {
  const r = TILT_RANGE_DEG[k];
  lines.push(`    case .${k}: return ${r ? `${lit(r.min)}...${lit(r.max)}` : 'nil'}`);
}
lines.push('    }');
lines.push('  }');
lines.push('}');
lines.push('');
writeFileSync(OUT, lines.join('\n'));
console.error(`[gen] ${entries.length} keys → ${OUT}`);
