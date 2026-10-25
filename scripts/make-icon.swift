import AppKit
import ImageIO
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(NSColor(white: 0.96, alpha: 1).cgColor)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setStrokeColor(NSColor(white: 0.83, alpha: 1).cgColor)
context.setLineWidth(1.5)
context.strokeEllipse(in: CGRect(x: 94, y: 94, width: 836, height: 836))
let rect = CGRect(x: 190, y: 190, width: 644, height: 644)
context.setFillColor(NSColor.white.cgColor)
context.fillEllipse(in: rect)
context.saveGState()
context.addEllipse(in: rect); context.clip()
context.setFillColor(NSColor(white: 0.045, alpha: 1).cgColor)
context.fill(CGRect(x: 512, y: 190, width: 322, height: 644))
context.fillEllipse(in: CGRect(x: 351, y: 512, width: 322, height: 322))
context.setFillColor(NSColor.white.cgColor)
context.fillEllipse(in: CGRect(x: 351, y: 190, width: 322, height: 322))
context.fillEllipse(in: CGRect(x: 467, y: 628, width: 90, height: 90))
context.setFillColor(NSColor(white: 0.045, alpha: 1).cgColor)
context.fillEllipse(in: CGRect(x: 467, y: 306, width: 90, height: 90))
context.restoreGState()
context.setStrokeColor(NSColor(white: 0.045, alpha: 1).cgColor)
context.setLineWidth(2); context.strokeEllipse(in: rect)
let image = context.makeImage()!
let imageDestination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(imageDestination, image, nil)
guard CGImageDestinationFinalize(imageDestination) else { fatalError("PNG export failed") }
