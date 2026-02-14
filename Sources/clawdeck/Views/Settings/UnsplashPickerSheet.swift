import SwiftUI

/// Sheet for browsing and selecting an Unsplash photo as the inner panel background.
/// Writes to @AppStorage on each selection for live preview; reverts on cancel.
struct UnsplashPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("bgMode") private var bgModeRaw: String = InnerPanelBackgroundMode.solidColor.rawValue
    @AppStorage("bgUnsplashURL") private var bgUnsplashURL: String = ""
    @AppStorage("bgUnsplashPhotographer") private var bgUnsplashPhotographer: String = ""

    /// Original values captured on appear, restored on cancel.
    @State private var originalMode: String = ""
    @State private var originalURL: String = ""
    @State private var originalPhotographer: String = ""

    @State private var searchText = ""
    @State private var photos: [UnsplashService.UnsplashPhoto] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var hoveredPhotoId: String?
    @State private var selectedPhotoId: String?

    private let service = UnsplashService()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    bgModeRaw = originalMode
                    bgUnsplashURL = originalURL
                    bgUnsplashPhotographer = originalPhotographer
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Choose Background Image")
                    .font(.headline)

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedPhotoId == nil)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search Unsplash…", text: $searchText)
                    .textFieldStyle(.plain)
                if isSearching {
                    ProgressView().controlSize(.small)
                }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            // Results grid
            if photos.isEmpty && !isSearching {
                ContentUnavailableView(
                    "Search for photos",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Type a keyword to find background images.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(photos) { photo in
                            AsyncImage(url: photo.thumbURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(Color.gray.opacity(0.2))
                            }
                            .frame(height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        selectedPhotoId == photo.id
                                            ? Color.accentColor
                                            : hoveredPhotoId == photo.id
                                                ? Color.accentColor.opacity(0.5)
                                                : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                            .onHover { isHovered in
                                hoveredPhotoId = isHovered ? photo.id : nil
                            }
                            .overlay(alignment: .bottomLeading) {
                                Text(photo.photographer)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(.black.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .padding(4)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedPhotoId = photo.id
                                bgModeRaw = InnerPanelBackgroundMode.unsplash.rawValue
                                bgUnsplashURL = photo.regularURL.absoluteString
                                bgUnsplashPhotographer = photo.photographer
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 520, height: 480)
        .onAppear {
            originalMode = bgModeRaw
            originalURL = bgUnsplashURL
            originalPhotographer = bgUnsplashPhotographer
        }
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await performSearch(query: newValue)
            }
        }
    }

    private func performSearch(query: String) async {
        isSearching = true
        do {
            photos = try await service.search(query: query)
        } catch {
            photos = []
        }
        isSearching = false
    }
}
