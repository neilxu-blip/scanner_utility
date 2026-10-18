import Foundation

/// The user-facing workflow, independent of the scanner used to acquire images.
public enum ScanWorkflowMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case auto, document, photo, custom, stitch, advanced

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: "Auto Scan"
        case .document: "Document Scan"
        case .photo: "Photo Scan"
        case .custom: "Custom Scan"
        case .stitch: "Scan and Stitch"
        case .advanced: "Advanced Scan"
        }
    }

    public var buttonTitle: String {
        switch self {
        case .auto: "Auto"
        case .document: "Document"
        case .photo: "Photo"
        case .custom: "Custom"
        case .stitch: "Stitch"
        case .advanced: "Advanced"
        }
    }

    public var symbol: String {
        switch self {
        case .auto: "square.stack"
        case .document: "doc.richtext"
        case .photo: "photo"
        case .custom: "slider.horizontal.3"
        case .stitch: "rectangle.split.2x1"
        case .advanced: "scanner"
        }
    }
}

public enum ScanOutputFormat: String, CaseIterable, Codable, Sendable {
    case automatic, pdf, jpeg, png, tiff

    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .pdf: "PDF (Multiple Pages)"
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .tiff: "TIFF"
        }
    }

    public var fileExtension: String {
        switch self {
        case .automatic, .pdf: "pdf"
        case .jpeg: "jpg"
        case .png: "png"
        case .tiff: "tiff"
        }
    }

    public var isPDF: Bool { self == .pdf || self == .automatic }
}

public enum ScanSource: String, CaseIterable, Codable, Sendable {
    case automatic, document, photo, magazine

    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .document: "Document"
        case .photo: "Photo"
        case .magazine: "Magazine"
        }
    }
}

public enum StitchDirection: String, CaseIterable, Codable, Sendable {
    case horizontal, vertical

    public var displayName: String {
        switch self {
        case .horizontal: "Left to right"
        case .vertical: "Top to bottom"
        }
    }
}
