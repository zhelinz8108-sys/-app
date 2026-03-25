import SwiftUI

struct GuestFormView: View {
    @Binding var name: String
    @Binding var idType: IDType
    @Binding var idNumber: String
    @Binding var phone: String
    @Binding var notes: String
    @Binding var numberOfGuests: Int

    @State private var showScanner = false

    var body: some View {
        Section("客人信息") {
            // 扫描身份证按钮
            Button {
                showScanner = true
            } label: {
                HStack {
                    Image(systemName: "camera.viewfinder")
                        .font(.title3)
                    Text("扫描身份证")
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }

            TextField("姓名 *", text: $name)
                .textContentType(.name)

            Picker("证件类型", selection: $idType) {
                ForEach(IDType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }

            TextField("证件号码 *", text: $idNumber)
                .textContentType(.oneTimeCode)
                .autocorrectionDisabled()

            TextField("手机号码 *", text: $phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)

            Stepper("入住人数: \(numberOfGuests)", value: $numberOfGuests, in: 1...10)

            TextField("备注（选填）", text: $notes)
        }
        .sheet(isPresented: $showScanner) {
            IDCardScannerView { result in
                name = result.name
                idNumber = result.idNumber
                idType = .idCard
            }
        }
    }
}
