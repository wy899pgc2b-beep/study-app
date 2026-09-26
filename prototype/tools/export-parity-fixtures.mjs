// 試作品(JS)の判定を、iPhone アプリ(Swift の StudyCore)に移すときの突き合わせ用のデータを書き出す。
// 試作品のテスト(test/analysis.test.js)が Analyzer に入れた特徴量と、そのときの判定の結果をすべて記録し、
// 特徴量の計算・キャリブレーション・位置合わせ・1 分ごとの集計の例も加えて、JSON に書き出す。
// 使い方:node tools/export-parity-fixtures.mjs(prototype/ で実行)
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULTS, APP_VERSION } from '../js/config.js';
import {
  Analyzer,
  SessionRecorder,
  checkFraming,
  computeCalibration,
  computeClosedReference,
  eyeSignalQuality,
  extractFeatures,
  learningStyle,
  scoreMinute,
} from '../js/analysis.js';

const here = dirname(fileURLToPath(import.meta.url));
const OUT = join(here, '../../ios/StudyCore/Tests/StudyCoreTests/Fixtures');
const copy = (x) => JSON.parse(JSON.stringify(x));
// 判定の結果(出力)は有効数字 10 桁に丸めて保存する(比べるときは誤差を許す)。入力は丸めない
const roundOut = (x) => JSON.parse(JSON.stringify(x, (k, v) => (typeof v === 'number' && Number.isFinite(v) && !Number.isInteger(v) ? Number(v.toPrecision(10)) : v)));
const q5 = (v) => Math.round(v * 1e5) / 1e5;

// --- 1. テストの中の Analyzer の実行をすべて記録する
const sessions = [];
const origUpdate = Analyzer.prototype.update;
const origSetCal = Analyzer.prototype.setCalibration;
function sessionOf(a) {
  if (!a.__session) {
    a.__session = { cfg: copy(a.cfg), options: { autoAway: a.autoAway, setup: a.setup }, ops: [] };
    sessions.push(a.__session);
  }
  return a.__session;
}
Analyzer.prototype.setCalibration = function (cal) {
  sessionOf(this).ops.push({ cal: cal == null ? null : copy(cal) });
  return origSetCal.call(this, cal);
};
Analyzer.prototype.update = function (f) {
  const s = sessionOf(this);
  const input = copy(f);
  const out = origUpdate.call(this, f);
  s.ops.push({ f: input, out: roundOut(out) });
  return out;
};

await import('../test/analysis.test.js');

// node:test はモジュールを読み込んだ後にテストを実行するので、終わってから書き出す
process.on('exit', () => {
  const used = sessions.filter((s) => s.ops.some((o) => o.f));
  mkdirSync(OUT, { recursive: true });
  writeFileSync(join(OUT, 'analyzer.json'), JSON.stringify({ appVersion: APP_VERSION, sessions: used }));

  // --- 2. 特徴量の計算(extractFeatures)
  writeFileSync(join(OUT, 'features.json'), JSON.stringify({ appVersion: APP_VERSION, cfg: DEFAULTS, cases: featureCases() }));

  // --- 3. キャリブレーション・目を閉じたときの基準・位置合わせ・1 分ごとの集計
  const calCases = [];
  const framingCases = [];
  const recorderCases = [];
  used.forEach((s, si) => {
    const frames = s.ops.filter((o) => o.f).map((o) => o.f);
    for (const [from, to] of [
      [0, 15],
      [5, 25],
    ]) {
      const feats = frames.slice(from, to);
      if (feats.length < 3) continue;
      for (const opts of [
        { measuredEyeDeskCm: 30, tiltDeg: 20 },
        { measuredEyeDeskCm: 35, tiltDeg: 0 },
      ]) {
        const cal = computeCalibration(feats, opts);
        const closedFeats = frames.slice(to, to + 15);
        const closedRef = cal ? computeClosedReference(closedFeats, cal, s.cfg) : null;
        const eyeSignal = cal ? eyeSignalQuality({ ...cal, closedRef }, s.cfg) : null;
        calCases.push({ session: si, from, to, opts, cal: cal == null ? null : roundOut(cal), closedFrom: to, closedTo: to + 15, closedRef: roundOut(closedRef), eyeSignal });
      }
    }
    frames.forEach((f, fi) => {
      if (fi % 7 !== 0) return;
      for (const setup of ['stand', 'landscape', 'tilt', 'flat']) {
        const r = checkFraming(f, { setup });
        framingCases.push({ session: si, frame: fi, setup, ok: r.ok, codes: r.issues.map((i) => i.code) });
      }
    });
    // 試作品の app.js と同じように、状態(離席中は away)と出来事を 1 分ごとに集計する
    const outs = s.ops.filter((o) => o.f);
    if (!outs.length) return;
    const startT = outs[0].f.t;
    for (const autoAway of [true, false]) {
      const rec = new SessionRecorder(startT, s.cfg, { autoAway });
      let prevT = null;
      for (const o of outs) {
        const t = o.f.t;
        const dt = prevT == null ? 0 : Math.min(1, (t - prevT) / 1000);
        prevT = t;
        rec.add(t, dt, o.out.away ? 'away' : o.out.state);
        for (const ev of o.out.events) rec.addEvent(ev);
      }
      recorderCases.push({ session: si, autoAway, startT, summary: roundOut(rec.summary()), minutes: roundOut(rec.minutes) });
    }
  });
  const scoreCases = [];
  const r = mulberry32(7);
  for (let i = 0; i < 200; i++) {
    const secs = { work: 0, think: 0, lookaway: 0, drowsy: 0, sleep: 0, absent: 0, away: 0, paused: 0 };
    let left = 60;
    for (const k of Object.keys(secs)) {
      const v = Math.round(r() * left * 10) / 10;
      secs[k] = v;
      left -= v;
    }
    const m = { secs, habits: Math.floor(r() * 8), interruptions: Math.floor(r() * 8) };
    scoreCases.push({ minute: m, autoAway: i % 2 === 0, score: scoreMinute(m, DEFAULTS, { autoAway: i % 2 === 0 }) });
  }
  const styleCases = [];
  for (let i = 0; i < 60; i++) {
    const n = Math.floor(r() * 50);
    const scores = Array.from({ length: n }, () => (r() < 0.1 ? null : Math.round(r() * 100)));
    const work = Math.round(r() * 3000);
    const think = Math.round(r() * 3000);
    styleCases.push({ work, think, scores, style: learningStyle(work, think, scores) });
  }
  writeFileSync(
    join(OUT, 'misc.json'),
    JSON.stringify({ appVersion: APP_VERSION, calibration: calCases, framing: framingCases, recorder: recorderCases, scoreMinute: scoreCases, learningStyle: styleCases }),
  );
  const frameCount = used.reduce((n, s) => n + s.ops.filter((o) => o.f).length, 0);
  console.error(`[export] sessions ${used.length}, frames ${frameCount}, calibration ${calCases.length}, framing ${framingCases.length}, recorder ${recorderCases.length} → ${OUT}`);
});

// 再現できる乱数
function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// 特徴量の計算の例:顔(478 点と表情係数)、手、上半身、髪の面積を、乱数で少しずつ変えて作る
function featureCases() {
  const r = mulberry32(42);
  const jitter = (s) => (r() - 0.5) * s;
  const cases = [];
  const BS = [
    'eyeBlinkLeft',
    'eyeBlinkRight',
    'eyeLookDownLeft',
    'eyeLookDownRight',
    'eyeLookUpLeft',
    'eyeLookUpRight',
    'eyeLookOutLeft',
    'eyeLookOutRight',
    'eyeLookInLeft',
    'eyeLookInRight',
    'jawOpen',
  ];
  for (let i = 0; i < 60; i++) {
    const [W, H] = i % 3 === 0 ? [720, 1280] : [1280, 960];
    const cx = 0.5 + jitter(0.2);
    const cy = 0.35 + jitter(0.2);
    const s = 0.12 + r() * 0.15;
    const face =
      i % 10 === 9
        ? null
        : {
            landmarks: Array.from({ length: i % 11 === 5 ? 468 : 478 }, () => ({ x: q5(cx + jitter(s)), y: q5(cy + jitter(s * 1.3)), z: q5(jitter(0.1)) })),
            blendshapes:
              i % 8 === 3
                ? null
                : Object.fromEntries(BS.filter(() => r() > 0.05).map((k) => [k, q5(r())])),
          };
    const hands = Array.from({ length: Math.floor(r() * 3) }, () => {
      const hx = r();
      const hy = 0.5 + r() * 0.55;
      return Array.from({ length: 21 }, () => ({ x: q5(hx + jitter(0.12)), y: q5(hy + jitter(0.12)), z: q5(jitter(0.05)) }));
    });
    const pose =
      i % 6 === 4
        ? null
        : Array.from({ length: 33 }, (_, k) => ({
            x: q5(cx + jitter(0.5)),
            y: q5(k === 11 || k === 12 ? cy + 0.3 + jitter(0.1) : cy + jitter(0.3)),
            z: q5(jitter(0.2)),
            visibility: q5(r() < 0.2 ? r() * 0.5 : 0.5 + r() * 0.5),
          }));
    const segment = i % 5 === 1 ? null : { crownRatio: r() < 0.1 ? null : r(), hairFrac: r() * 0.2, faceSkinFrac: r() * 0.1, personFrac: r() };
    const frame = {
      t: i * 200,
      width: W,
      height: H,
      face,
      hands,
      pose,
      brightness: i % 4 === 2 ? null : 20 + r() * 200,
      cameraTiltDeg: i % 3 === 1 ? null : r() * 40,
      segment,
    };
    cases.push({ frame, features: roundOut(extractFeatures(frame, DEFAULTS)) });
  }
  return cases;
}
