import CoreGraphics
import Foundation
import ImageIO

nonisolated enum PhotoMetadata {

    private static let exifKeys: [String] = [
        kCGImagePropertyExifExposureTime as String,
        kCGImagePropertyExifFNumber as String,
        kCGImagePropertyExifISOSpeedRatings as String,
        kCGImagePropertyExifFocalLength as String,
        kCGImagePropertyExifFocalLenIn35mmFilm as String,
        kCGImagePropertyExifLensMake as String,
        kCGImagePropertyExifLensModel as String,
        kCGImagePropertyExifExposureBiasValue as String,
        kCGImagePropertyExifBrightnessValue as String,
        kCGImagePropertyExifMeteringMode as String,
        kCGImagePropertyExifWhiteBalance as String,
        kCGImagePropertyExifFlash as String,
        kCGImagePropertyExifDateTimeOriginal as String,
        kCGImagePropertyExifDateTimeDigitized as String
    ]

    private static let tiffKeys: [String] = [
        kCGImagePropertyTIFFMake as String,
        kCGImagePropertyTIFFModel as String
    ]

    static func properties(from capture: Data?, capturedAt date: Date = .now) -> [String: Any] {
        var exif: [String: Any] = [:]
        var tiff: [String: Any] = [:]

        if let capture,
           let source = CGImageSourceCreateWithData(capture as CFData, nil),
           let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            let sourceExif = original[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
            for key in exifKeys {
                if let value = sourceExif[key] { exif[key] = value }
            }
            let sourceTiff = original[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
            for key in tiffKeys {
                if let value = sourceTiff[key] { tiff[key] = value }
            }
        }

        let originalDate = kCGImagePropertyExifDateTimeOriginal as String
        if exif[originalDate] == nil {
            exif[originalDate] = exifTimestamp(date)
        }
        tiff[kCGImagePropertyTIFFSoftware as String] = "Onyx"
        tiff[kCGImagePropertyTIFFOrientation as String] = 1

        return [
            kCGImagePropertyOrientation as String: 1,
            kCGImagePropertyExifDictionary as String: exif,
            kCGImagePropertyTIFFDictionary as String: tiff
        ]
    }

    private static func exifTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
