import SwiftUI
import PhotosUI

/// 小票拍照/选图组件
struct ReceiptCameraView: View {
    let depositID: String
    @Binding var hasReceipt: Bool
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var receiptImage: UIImage?
    @State private var showFullImage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = receiptImage {
                // 已有照片 — 显示缩略图
                Button { showFullImage = true } label: {
                    HStack(spacing: 10) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("POS小票已拍")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.green)
                            Text("点击查看大图")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            showActionSheet()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            } else {
                // 无照片 — 拍照按钮
                HStack(spacing: 8) {
                    Button {
                        showCamera = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "camera.fill")
                            Text("拍POS小票")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                    }
                    Button {
                        showPhotoPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "photo")
                            Text("从相册选")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .onAppear {
            receiptImage = ReceiptImageService.load(depositID: depositID)
        }
        .fullScreenCover(isPresented: $showCamera) {
            ImagePickerView(sourceType: .camera) { image in
                saveImage(image)
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            ImagePickerView(sourceType: .photoLibrary) { image in
                saveImage(image)
            }
        }
        .fullScreenCover(isPresented: $showFullImage) {
            if let image = receiptImage {
                ReceiptFullScreenView(image: image)
            }
        }
    }

    private func saveImage(_ image: UIImage) {
        if ReceiptImageService.save(depositID: depositID, image: image) {
            receiptImage = image
            hasReceipt = true
        }
    }

    private func showActionSheet() {
        showCamera = true // 简化：重新拍照覆盖
    }
}

/// 全屏查看小票
struct ReceiptFullScreenView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            .background(Color.black)
            .navigationTitle("POS小票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

/// UIKit 相机/相册包装
struct ImagePickerView: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, dismiss: dismiss)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImagePicked: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImagePicked = onImagePicked
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
