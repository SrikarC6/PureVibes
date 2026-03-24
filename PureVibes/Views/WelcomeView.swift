import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.purevibes.app", category: "WelcomeView")

struct WelcomeView: View {
    let onFolderSelected: ([URL]) -> Void
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80, weight: .thin))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .accentColor.opacity(0.4), radius: 20)

                Text("Welcome to PureVibes")
                    .font(.custom("Baskerville", size: 42).bold())
                    .foregroundColor(.white)

                Text("Select a folder containing your music library to get started.")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Scanning library…")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            } else {
                Button(action: selectFolder) {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus")
                        Text("Choose Music Folder")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Select one or more folders containing your music"

        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard !urls.isEmpty else { return }

        // Save security-scoped bookmarks
        for url in urls {
            PersistenceService.shared.saveBookmark(for: url)
        }

        UserDefaults.standard.set(true, forKey: DefaultsKey.hasLaunchedBefore)
        logger.info("First launch complete: \(urls.count) folder(s) selected")

        isLoading = true
        onFolderSelected(urls)
    }
}
