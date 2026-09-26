import Foundation

/// selfie_multiclass の分類の番号(0:背景 1:髪 2:体の肌 3:顔の肌 4:服 5:その他)
public enum SegmentClass: UInt8, Sendable {
  case background = 0
  case hair = 1
  case bodySkin = 2
  case faceSkin = 3
  case clothes = 4
  case others = 5
}

/// 分類の結果(画素ごとの番号)から、髪・顔の肌・人の面積の割合を求める。step 画素ごとに間引いて数える。
/// 試作品の vision.js の segmentStats と同じ計算。画素がなければ nil。
public func segmentStats(mask: UnsafeBufferPointer<UInt8>, width: Int, height: Int, step: Int = 4) -> SegmentStats? {
  guard width > 0, height > 0, step > 0, mask.count >= width * height else { return nil }
  var counts = [Int](repeating: 0, count: 6)
  var total = 0
  var hairYSum = 0
  var y = 0
  while y < height {
    let row = y * width
    var x = 0
    while x < width {
      let c = Int(mask[row + x])
      if c < counts.count { counts[c] += 1 }
      if c == Int(SegmentClass.hair.rawValue) { hairYSum += y }
      total += 1
      x += step
    }
    y += step
  }
  if total == 0 { return nil }
  let hairCount = counts[Int(SegmentClass.hair.rawValue)]
  let hair = Double(hairCount) / Double(total)
  let face = Double(counts[Int(SegmentClass.faceSkin.rawValue)]) / Double(total)
  return SegmentStats(
    // 頭頂部の見える割合:頭(髪+顔の肌)のうち髪の占める割合。うつむくほど大きくなる
    crownRatio: hair + face > 0.002 ? hair / (hair + face) : nil,
    hairFrac: hair,
    faceSkinFrac: face,
    personFrac: 1 - Double(counts[Int(SegmentClass.background.rawValue)]) / Double(total),
    hairCenterY: hairCount > 0 ? Double(hairYSum) / Double(hairCount) / Double(height) : nil
  )
}

public func segmentStats(mask: [UInt8], width: Int, height: Int, step: Int = 4) -> SegmentStats? {
  mask.withUnsafeBufferPointer { segmentStats(mask: $0, width: width, height: height, step: step) }
}
