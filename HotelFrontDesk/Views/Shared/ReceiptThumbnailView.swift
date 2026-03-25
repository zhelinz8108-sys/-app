import SwiftUI

/// 延迟加载小票图片，点击时才从磁盘加载全尺寸图片
struct ReceiptThumbnailLazyView: View {
    let depositID: String
    @State private var loadedImage: UIImage?
    @State private var showFull = false

    var body: some View {
        Button {
            if loadedImage == nil {
                loadedImage = ReceiptImageService.load(depositID: depositID)
            }
            if loadedImage != nil {
                showFull = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.richtext")
                    .frame(width: 50, height: 35)
                Text("POS小票")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .fullScreenCover(isPresented: $showFull) {
            if let img = loadedImage {
                ReceiptFullScreenView(image: img)
            }
        }
    }
}

/// 小票缩略图，点击可全屏查看
struct ReceiptThumbnailView: View {
    let image: UIImage
    @State private var showFull = false

    var body: some View {
        Button { showFull = true } label: {
            HStack(spacing: 8) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 35)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text("POS小票")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .fullScreenCover(isPresented: $showFull) {
            ReceiptFullScreenView(image: image)
        }
    }
}
