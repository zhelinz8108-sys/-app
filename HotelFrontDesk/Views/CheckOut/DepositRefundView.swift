import SwiftUI

struct DepositRefundView: View {
    @ObservedObject var viewModel: CheckOutViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("退押金")
                .font(.headline)

            let summary = viewModel.depositSummary

            // 押金概况
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("已收押金")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("¥\(Int(summary.totalCollected))")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading) {
                    Text("已退")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("¥\(Int(summary.totalRefunded))")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                }

                VStack(alignment: .leading) {
                    Text("待退余额")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("¥\(Int(summary.balance))")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            if summary.balance > 0 {
                // 退款金额输入
                HStack {
                    Text("退款金额 ¥")
                    TextField("金额", text: $viewModel.refundAmount)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }

                // 快捷选择金额
                HStack(spacing: 8) {
                    quickAmountButton(amount: summary.balance, label: "全额退")
                    if summary.balance >= 200 {
                        quickAmountButton(amount: 100, label: "¥100")
                    }
                    if summary.balance >= 500 {
                        quickAmountButton(amount: 200, label: "¥200")
                    }
                }

                // 退款方式
                VStack(alignment: .leading, spacing: 6) {
                    Text("退款方式")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(PaymentMethod.allCases) { method in
                                Button {
                                    viewModel.refundPaymentMethod = method
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: method.icon)
                                            .font(.caption2)
                                        Text(method.rawValue)
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(viewModel.refundPaymentMethod == method ? Color.green : Color(.tertiarySystemBackground))
                                    .foregroundStyle(viewModel.refundPaymentMethod == method ? .white : .primary)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }

                // POS回单号
                TextField("POS回单号（选填）", text: $viewModel.refundNotes)
                    .textFieldStyle(.roundedBorder)

                // 退押金按钮
                Button {
                    viewModel.isSubmitting = true
                    Task { await viewModel.performRefund() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSubmitting {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text("确认退押金 ¥\(Int(viewModel.refundValue))")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(viewModel.canRefund ? Color.green : Color.gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!viewModel.canRefund || viewModel.isSubmitting)

                if viewModel.refundValue > summary.balance {
                    Text("退款金额不能超过余额 ¥\(Int(summary.balance))")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                Text("押金已全部退还")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func quickAmountButton(amount: Double, label: String) -> some View {
        Button {
            viewModel.refundAmount = String(format: "%.0f", amount)
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
                .clipShape(Capsule())
        }
    }
}
