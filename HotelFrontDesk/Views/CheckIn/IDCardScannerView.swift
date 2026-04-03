import SwiftUI
import AVFoundation
import Vision

// MARK: - 扫描结果
struct IDCardScanResult: Equatable {
    var name: String
    var idNumber: String
}

// MARK: - OCR 模式
enum OCRMode: String, CaseIterable {
    case local = "本地识别"
    case paddleOCR = "PaddleOCR"

    var description: String {
        switch self {
        case .local: return "Apple Vision（无需网络）"
        case .paddleOCR: return "PaddleOCR（识别更准）"
        }
    }
}

// MARK: - 身份证扫描视图
struct IDCardScannerView: View {
    var onResult: (IDCardScanResult) -> Void
    var onExtendedResult: ((IDCardScanResultExtended) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = IDCardScanner()
    @State private var ocrMode: OCRMode = {
        let saved = UserDefaults.standard.string(forKey: "ocrMode") ?? ""
        return OCRMode(rawValue: saved) ?? .paddleOCR
    }()
    @State private var paddleOCRAvailable = false

    init(onResult: @escaping (IDCardScanResult) -> Void,
         onExtendedResult: ((IDCardScanResultExtended) -> Void)? = nil) {
        self.onResult = onResult
        self.onExtendedResult = onExtendedResult
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 相机预览
                if scanner.isCameraAvailable {
                    CameraPreviewView(session: scanner.session)
                        .ignoresSafeArea()

                    VStack {
                        // OCR 模式切换
                        HStack(spacing: 8) {
                            ForEach(OCRMode.allCases, id: \.self) { mode in
                                Button {
                                    ocrMode = mode
                                    UserDefaults.standard.set(mode.rawValue, forKey: "ocrMode")
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: mode == .local ? "eye" : "server.rack")
                                            .font(.caption2)
                                        Text(mode.rawValue)
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(ocrMode == mode ? Color.blue : Color.black.opacity(0.5))
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                                }
                                .disabled(mode == .paddleOCR && !paddleOCRAvailable)
                                .opacity(mode == .paddleOCR && !paddleOCRAvailable ? 0.5 : 1)
                            }
                        }
                        .padding(.top, 60)

                        if ocrMode == .paddleOCR && paddleOCRAvailable {
                            Text("🔥 PaddleOCR 增强识别")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .padding(.top, 4)
                        }

                        Spacer()

                        // 身份证对齐引导框
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
                                Text(ocrMode == .paddleOCR ? "PaddleOCR 识别中..." : "识别中...")
                                    .foregroundStyle(.white)
                            }
                            .padding()
                        } else if let error = scanner.errorMessage {
                            Text(error)
                                .foregroundStyle(.orange)
                                .font(.subheadline)
                                .padding()
                        } else if let ext = scanner.extendedResult {
                            // 显示识别置信度
                            Text("✅ 识别成功 (置信度: \(Int(ext.confidence * 100))%)")
                                .foregroundStyle(.green)
                                .font(.subheadline)
                                .padding()
                        }

                        // 拍照按钮
                        Button {
                            scanner.ocrMode = ocrMode
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
                    if let ext = scanner.extendedResult {
                        onExtendedResult?(ext)
                    }
                    dismiss()
                }
            }
            .onAppear {
                scanner.startSession()
                // 检查 PaddleOCR 服务是否可用
                Task {
                    paddleOCRAvailable = await PaddleOCRService.shared.isAvailable()
                    if !paddleOCRAvailable && ocrMode == .paddleOCR {
                        ocrMode = .local
                    }
                }
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
    @Published var extendedResult: IDCardScanResultExtended?
    @Published var isProcessing = false
    @Published var errorMessage: String?

    var ocrMode: OCRMode = .paddleOCR

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

    // MARK: - PaddleOCR 识别（远程）
    private func recognizeWithPaddleOCR(from image: UIImage) {
        Task {
            do {
                let result = try await PaddleOCRService.shared.recognize(image: image)
                self.extendedResult = result
                self.scanResult = result.basic
                self.isProcessing = false
            } catch {
                self.isProcessing = false
                self.errorMessage = "PaddleOCR: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Apple Vision OCR 识别（本地）
    private func recognizeWithVision(from image: CGImage) {
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

    // MARK: - 解析身份证文字（本地 Vision 模式）
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

            if trimmed.contains("姓名") {
                let afterName = trimmed.replacingOccurrences(of: "姓名", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !afterName.isEmpty {
                    name = afterName
                } else if index + 1 < texts.count {
                    name = texts[index + 1].trimmingCharacters(in: .whitespaces)
                }
            }

            if trimmed.hasPrefix("名") && trimmed.count > 1 {
                let candidate = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty && name == nil {
                    name = candidate
                }
            }
        }

        // 启发式姓名检测
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

            // 根据模式选择 OCR 引擎
            switch self.ocrMode {
            case .paddleOCR:
                self.recognizeWithPaddleOCR(from: uiImage)
            case .local:
                self.recognizeWithVision(from: cgImage)
            }
        }
    }
}
