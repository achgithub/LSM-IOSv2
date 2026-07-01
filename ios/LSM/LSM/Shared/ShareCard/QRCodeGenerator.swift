import CoreImage.CIFilterBuiltins
import UIKit

/// Pure QR-code rendering via CoreImage's built-in generator — no third-party
/// dependency needed. Used for the player-link share card (spec: a visual,
/// trustworthy-looking way to hand someone a link, since long UUID URLs read
/// as suspicious to less tech-savvy players).
enum QRCodeGenerator {
    /// Renders `string` as a QR code, upscaled `scale`x from CoreImage's native
    /// (small, blocky) output so edges stay crisp rather than blurry when placed
    /// in a card. Returns nil if the string can't be encoded (extremely long
    /// input) or the underlying CIImage can't be rasterized.
    static func image(for string: String, scale: CGFloat = 10) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
