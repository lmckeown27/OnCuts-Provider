import SwiftUI
#if canImport(UIKit)
import UIKit

struct ProviderProfileImageCameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProviderProfileImageCameraPicker

        init(parent: ProviderProfileImageCameraPicker) {
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
            guard let image = info[.originalImage] as? UIImage else { return }
            parent.onImagePicked(image)
        }
    }
}
#endif
