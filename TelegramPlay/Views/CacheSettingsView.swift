import SwiftUI

struct CacheSettingsView: View {
    @ObservedObject var cache: CacheManager

    var body: some View {
        Form {
            Section("Storage") {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progressFraction)
                        .tint(usedFraction > 1 ? .red : .accentColor)
                    Text("\(formatBytes(cache.usedBytes)) of \(formatBytes(cache.limitBytes)) used")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                if let last = cache.lastCleanupDate {
                    Text("Last cleanup: \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task { await cache.clearCacheNow() }
                } label: {
                    HStack {
                        Text("Clean up now")
                        Spacer()
                        if cache.isCleaning {
                            ProgressView()
                        }
                    }
                }
                .disabled(cache.isCleaning)
            } footer: {
                Text("Clears downloaded videos and media on this device. Chat history stays; videos re-download when you play again.")
            }

            if let error = cache.lastError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Cache")
        .task {
            await cache.refreshStatistics()
        }
        .refreshable {
            await cache.refreshStatistics()
        }
    }

    private var usedFraction: Double {
        guard cache.limitBytes > 0 else { return 0 }
        return Double(cache.usedBytes) / Double(cache.limitBytes)
    }

    private var progressFraction: Double {
        min(usedFraction, 1)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
