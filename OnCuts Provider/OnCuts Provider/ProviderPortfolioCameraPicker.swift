import SwiftUI
#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers

struct ProviderPortfolioCameraPicker: UIViewControllerRepresentable {
    enum Capture {
        case photo
        case video
        case both
    }

    @Environment(\.dismiss) private var dismiss
    var capture: Capture
    var onPhoto: (UIImage) -> Void
    var onVideo: (Data, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        switch capture {
        case .photo:
            picker.mediaTypes = [UTType.image.identifier]
            picker.cameraCaptureMode = .photo
        case .video:
            picker.mediaTypes = [UTType.movie.identifier]
            picker.cameraCaptureMode = .video
            picker.videoQuality = .typeMedium
        case .both:
            picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
            picker.videoQuality = .typeMedium
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProviderPortfolioCameraPicker

        init(parent: ProviderPortfolioCameraPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.dismiss()
            if let image = info[.originalImage] as? UIImage {
                parent.onPhoto(image)
                return
            }
            if let url = info[.mediaURL] as? URL, let data = try? Data(contentsOf: url) {
                parent.onVideo(data, "video/quicktime")
            }
        }
    }
}
#endif
