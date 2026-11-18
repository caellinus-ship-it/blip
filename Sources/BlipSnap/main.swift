// blip-snap: renders one Scene frame to a PNG so the look can be checked by eye.
//
//   blip-snap --creature <c> --ship <s> --trail <t> --color <preset> --tick <n> --out <file.png>
//             [--dismiss <tick>] [--thinking]

import BlipCore
import CoreGraphics
import Foundation
import ImageIO

let bufferWidth = 240, bufferHeight = 200, scale = 3
let background: RGBA = 0x12121CFF
let colorPresets: [String: TrailColor] = [
  "fire": .fire, "pink": .pink, "cyan": .cyan, "lime": .lime, "violet": .violet,
]
let usage = """
  usage: blip-snap --creature <\(Creature.allCases.map(\.rawValue).joined(separator: "|"))>
                   --ship <\(Ship.allCases.map(\.rawValue).joined(separator: "|"))>
                   --trail <\(TrailStyle.allCases.map(\.rawValue).joined(separator: "|"))>
                   --color <\(colorPresets.keys.sorted().joined(separator: "|"))>
                   --tick <n> --out <file.png> [--dismiss <tick>] [--thinking]
  """

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("blip-snap: \(message)\n\(usage)\n".utf8))
  exit(2)
}

func parse<T>(_ flag: String, _ value: String, _ make: (String) -> T?) -> T {
  guard let v = make(value) else { fail("bad value '\(value)' for \(flag)") }
  return v
}

var settings = BlipSettings()
var ticks = 60
var dismissAt: Int?
var outPath: String?
var thinking = false

var args = CommandLine.arguments.dropFirst().makeIterator()
while let flag = args.next() {
  if flag == "--thinking" { thinking = true; continue }
  guard let value = args.next() else { fail("missing value for \(flag)") }
  switch flag {
  case "--creature": settings.creature = parse(flag, value, Creature.init(rawValue:))
  case "--ship": settings.ship = parse(flag, value, Ship.init(rawValue:))
  case "--trail": settings.trail = parse(flag, value, TrailStyle.init(rawValue:))
  case "--color": settings.trailColor = parse(flag, value) { colorPresets[$0] }
  case "--tick": ticks = parse(flag, value) { Int($0).flatMap { $0 >= 0 ? $0 : nil } }
  case "--out": outPath = value
  case "--dismiss": dismissAt = parse(flag, value) { Int($0).flatMap { $0 >= 0 ? $0 : nil } }
  default: fail("unknown option \(flag)")
  }
}
guard let outPath else { fail("--out is required") }

var scene = Scene(settings: settings, bufferWidth: bufferWidth, bufferHeight: bufferHeight, seed: 1)
scene.thinking = thinking
for t in 0..<ticks {
  if t == dismissAt { scene.dismiss() }
  scene.tick()
}

var buffer = PixelBuffer(width: bufferWidth, height: bufferHeight)
buffer.fill(x: 0, y: 0, w: bufferWidth, h: bufferHeight, background)
scene.render(into: &buffer)

// Expand each arcade pixel to a scale x scale block of RGBA bytes.
let width = bufferWidth * scale, height = bufferHeight * scale
var bytes = [UInt8](repeating: 0, count: width * height * 4)
for py in 0..<height {
  for px in 0..<width {
    let c = buffer.pixel(x: px / scale, y: py / scale)
    let i = (py * width + px) * 4
    bytes[i] = UInt8((c >> 24) & 0xFF)
    bytes[i + 1] = UInt8((c >> 16) & 0xFF)
    bytes[i + 2] = UInt8((c >> 8) & 0xFF)
    bytes[i + 3] = UInt8(c & 0xFF)
  }
}

let url = URL(fileURLWithPath: outPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
guard
  let provider = CGDataProvider(data: Data(bytes) as CFData),
  let image = CGImage(
    width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
  let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
else { fail("could not create the image for \(outPath)") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fail("could not write \(outPath)") }
print(outPath)
