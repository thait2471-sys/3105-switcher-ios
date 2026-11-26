import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var patchStore: PatchProjectStore
    @State private var selectedItemIndex: Int = 0
    @State private var isWorking = false
    @State private var statusMessage = "Sẵn sàng"
    @State private var showImporter = false
    @State private var actionAlert: PatchStoreAlert?

    private var currentItem: PatchLibraryItem? {
        guard !patchStore.items.isEmpty, selectedItemIndex < patchStore.items.count else { return nil }
        return patchStore.items[selectedItemIndex]
    }

    private var currentReceipt: PatchTransactionReceipt? {
        guard let project = currentItem?.project else { return nil }
        return DevicePatchService.latestReceipt(projectID: project.id)
    }

    private var isPatchApplied: Bool {
        currentReceipt != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 24) {
                    // 1. Trạng Thái Hoạt Động (Status Banner)
                    VStack(spacing: 10) {
                        Image(systemName: isPatchApplied ? "bolt.shield.fill" : "shield.slash")
                            .font(.system(size: 56))
                            .foregroundColor(isPatchApplied ? .green : .secondary)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isPatchApplied)

                        Text(isPatchApplied ? "PATCH ĐANG BẬT" : "GAME GỐC (CHƯA MOD)")
                            .font(.title3.weight(.bold))
                            .foregroundColor(isPatchApplied ? .green : .primary)

                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(20)
                    .padding(.horizontal)

                    // 2. CẦN GẠT BẬT / TẮT (Toggle Switch)
                    VStack(spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { isPatchApplied },
                            set: { newValue in
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if newValue {
                                    applyCurrentPatch()
                                } else {
                                    restoreCurrentPatch()
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Trạng Thái Patch")
                                    .font(.headline)
                                Text(isPatchApplied ? "Gạt tắt để khôi phục về game gốc 100%" : "Gạt bật để cài patch mod vào game")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .green))
                        .disabled(isWorking || currentItem == nil)
                    }
                    .padding(20)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(20)
                    .padding(.horizontal)

                    // 3. Chọn Gói Patch & Nhập Thêm File
                    VStack(spacing: 16) {
                        if !patchStore.items.isEmpty {
                            HStack {
                                Text("Gói Patch Mục Tiêu:")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Picker("Chọn Patch", selection: $selectedItemIndex) {
                                    ForEach(0..<patchStore.items.count, id: \.self) { idx in
                                        Text(patchStore.items[idx].project?.name ?? patchStore.items[idx].packageURL.lastPathComponent)
                                            .tag(idx)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                            }
                        } else {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Text("Chưa có gói patch nào.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }

                        Divider()

                        // Nút Thêm File Patch (.3105)
                        Button(action: { showImporter = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.accentColor)
                                Text("Nhập Gói Patch Mới (.3105)")
                                    .font(.body.weight(.medium))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.tertiaryLabel)
                            }
                        }
                    }
                    .padding(20)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(20)
                    .padding(.horizontal)

                    if isWorking {
                        ProgressView("Đang xử lý container...")
                            .padding()
                    }

                    Spacer()
                }
                .padding(.top)
            }
            .navigationTitle("3105 Switcher")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType(filenameExtension: "3105") ?? .data, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        patchStore.importPackage(from: url)
                        statusMessage = "Đã nhập thành công gói patch!"
                    }
                case .failure(let error):
                    statusMessage = "Lỗi nhập file: \(error.localizedDescription)"
                }
            }
            .alert(item: $actionAlert) { alert in
                Alert(
                    title: Text(alert.titleKey == "common.done" ? "Thành Công" : "Lỗi"),
                    message: Text(alert.message(language: language)),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    // HÀM BẬT PATCH (Apply)
    private func applyCurrentPatch() {
        guard let item = currentItem, let project = item.project else {
            statusMessage = "Không tìm thấy dữ liệu patch."
            return
        }
        isWorking = true
        statusMessage = "Đang sao lưu file gốc và chép patch vào game..."
        Task.detached(priority: .userInitiated) {
            do {
                _ = try DevicePatchService.apply(project: project)
                await MainActor.run {
                    patchStore.reload()
                    isWorking = false
                    statusMessage = "🟢 Đã BẬT mod thành công!"
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    statusMessage = "❌ Lỗi khi BẬT: \(error.localizedDescription)"
                }
            }
        }
    }

    // HÀM TẮT PATCH (Restore)
    private func restoreCurrentPatch() {
        guard let receipt = currentReceipt else {
            statusMessage = "Chưa có bản sao lưu nào để khôi phục."
            return
        }
        isWorking = true
        statusMessage = "Đang khôi phục lại game nguyên bản..."
        Task.detached(priority: .userInitiated) {
            do {
                try DevicePatchService.restore(receipt: receipt, allowChangedTargets: true)
                await MainActor.run {
                    patchStore.reload()
                    isWorking = false
                    statusMessage = "⚪ Đã TẮT mod: Game đã trở về nguyên bản!"
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    statusMessage = "❌ Lỗi khi khôi phục: \(error.localizedDescription)"
                }
            }
        }
    }
}
