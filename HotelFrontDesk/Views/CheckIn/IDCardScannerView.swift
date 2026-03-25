import SwiftUI
import AVFoundation
import Vision

// MARK: - 扫描结果
struct IDCardScanResult: Equatable {
    var name: String
    var idNumber: String
}

// MARK: - 身份证扫描视图
struct IDCardScannerView: View {
    var onResult: (IDCardScanResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = IDCardScanner()
    @State private var showNoCameraAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                // 相机预览
                if scanner.isCameraAvailable {
                    CameraPreviewView(session: scanner.session)
                        .ignoresSafeArea()

                    // 身份证对齐引导框
                    VStack {
                        Spacer()

                        RoundedRectangle(cornerRadius: 12)
                            .stroke(style: StrokeStyle(lineWidth: 3, dash: [10]))
                            .foregroundStyle(.white)
                            .frame(width: 340, height: 215)
                            .overlay(
                                Text("将身份证正面对准此框")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                                    .offset(y: -85)
                            )

                        Spacer()

                        // 状态提示
                        if scanner.isProcessing {
                            HStack {
                                ProgressView()
                                    .tint(.white)
                                Text("识别中...")
                                    .foregroundStyle(.white)
                            }
                            .padding()
                        } else if let error = scanner.errorMessage {
                            Text(error)
                                .foregroundStyle(.orange)
                                .font(.subheadline)
                                .padding()
                        }

                        // 拍照按钮
                        Button {
                            scanner.capturePhoto()
                        } label: {
                            Circle()
                                .fill(.white)
                                .frame(width: 70, height: 70)
                                .overlay(
                                    Circle()
                                        .stroke(.white.opacity(0.5), lineWidth: 4)
                                        .frame(width: 80, height: 80)
                                )
                        }
                        .disabled(scanner.isProcessing)
                        .padding(.bottom, 30)
                    }
                } else {
                    // 没有相机（模拟器）
                    ContentUnavailableView(
                        "无法使用相机",
                        systemImage: "camera.slash",
                        description: Text("请在真机 iPad 上使用扫描功能")
                    )
                }
            }
            .navigationTitle("扫描身份证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onChange(of: scanner.scanResult) { _, result in
                if let result {
                    onResult(result)
                    dismiss()
                }
            }
            .onAppear {
                scanner.startSession()
            }
            .onDisappear {
                scanner.stopSession()
            }
        }
    }
}

// MARK: - 相机预览 UIViewRepresentable
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - 身份证扫描器
@MainActor
final class IDCardScanner: NSObject, ObservableObject {
    @Published var scanResult: IDCardScanResult?
    @Published var isProcessing = false
    @Published var errorMessage: String?

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()

    var isCameraAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    func startSession() {
        guard isCameraAvailable else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo

        if session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()

        Task.detached { [session] in
            session.startRunning()
        }
    }

    func stopSession() {
        Task.detached { [session] in
            session.stopRunning()
        }
    }

    func capturePhoto() {
        guard !isProcessing else { return }
        isProcessing = true
        errorMessage = nil

        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - OCR 识别
    private func recognizeText(from image: CGImage) {
        let request = VNRecognizeTextRequest { [weak self] request, error in
            Task { @MainActor in
                guard let self else { return }
                self.isProcessing = false

                if let error {
                    self.errorMessage = "识别失败: \(error.localizedDescription)"
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    self.errorMessage = "未识别到文字，请重试"
                    return
                }

                let allText = observations.compactMap { $0.topCandidates(1).first?.string }
                let result = self.parseIDCard(texts: allText)

                if let result {
                    self.scanResult = result
                } else {
                    self.errorMessage = "未识别到身份证信息，请对准重试"
                }
            }
        }

        request.recognitionLanguages = ["zh-Hans", "en"]
        request.recognitionLevel = .accurate

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        Task.detached {
            try? handler.perform([request])
        }
    }

    // MARK: - 解析身份证文字
    private func parseIDCard(texts: [String]) -> IDCardScanResult? {
        let fullText = texts.joined(separator: " ")
        var name: String?
        var idNumber: String?

        // 提取身份证号：18位数字，最后一位可能是X
        if let regex = try? NSRegularExpression(pattern: "\\d{17}[\\dX]"),
           let match = regex.firstMatch(in: fullText, range: NSRange(fullText.startIndex..., in: fullText)),
           let range = Range(match.range, in: fullText) {
            idNumber = String(fullText[range])
        }

        // 提取姓名：「姓名」后面的文字
        for (index, text) in texts.enumerated() {
            let trimmed = text.trimmingCharacters(in: .whitespaces)

            // 方式1：同一行包含「姓名」
            if trimmed.contains("姓名") {
                let afterName = trimmed.replacingOccurrences(of: "姓名", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !afterName.isEmpty {
                    name = afterName
                }
                // 方式2：下一行是姓名
                else if index + 1 < texts.count {
                    name = texts[index + 1].trimmingCharacters(in: .whitespaces)
                }
            }

            // 方式3：如果文本中有「名」字开头（OCR可能把姓名拆开）
            if trimmed.hasPrefix("名") && trimmed.count > 1 {
                let candidate = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty && name == nil {
                    name = candidate
                }
            }
        }

        // 如果没通过「姓名」关键字找到，尝试用位置推断
        // 身份证上姓名通常是纯中文2-4个字，且不包含数字
        if name == nil {
            for text in texts {
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                let isChineseName = trimmed.count >= 2 && trimmed.count <= 4
                    && trimmed.allSatisfy { $0 >= "\u{4e00}" && $0 <= "\u{9fff}" }
                if isChineseName
                    && !trimmed.contains("姓名") && !trimmed.contains("性别")
                    && !trimmed.contains("民族") && !trimmed.contains("住址")
                    && !trimmed.contains("公民") {
                    name = trimmed
                    break
                }
            }
        }

        // 至少要识别到身份证号才返回结果
        guard let idNumber else { return nil }

        return IDCardScanResult(
            name: name ?? "",
            idNumber: idNumber
        )
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension IDCardScanner: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        Task { @MainActor in
            if let error {
                self.isProcessing = false
                self.errorMessage = "拍照失败: \(error.localizedDescription)"
                return
            }

            guard let data = photo.fileDataRepresentation(),
                  let uiImage = UIImage(data: data),
                  let cgImage = uiImage.cgImage else {
                self.isProcessing = false
                self.errorMessage = "图片处理失败"
                return
            }

            self.recognizeText(from: cgImage)
        }
    }
}
