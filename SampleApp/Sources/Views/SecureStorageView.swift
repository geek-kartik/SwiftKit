import SwiftUI
import SwiftKit

/// UI for demonstrating `SecureStorageProtocol` CRUD, error states, and Codable persistence.
public struct SecureStorageView: View {
    @StateObject private var viewModel = SecureStorageViewModel()

    public init() {}

    public var body: some View {
        Form {
            // String CRUD Section
            Section(header: Text("String Key-Value Persistence")) {
                TextField("Key", text: $viewModel.inputKey)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                TextField("Value", text: $viewModel.inputValue)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    Button(action: { viewModel.saveString() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .renderingMode(.template)
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: { viewModel.readString() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .renderingMode(.template)
                            Text("Read")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: { viewModel.updateString() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .renderingMode(.template)
                            Text("Update")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive, action: { viewModel.removeKey() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.fill")
                                .renderingMode(.template)
                            Text("Delete")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.vertical, 4)

                Button("Check Key Exists (contains)") {
                    viewModel.checkContains()
                }

                if let exists = viewModel.containsKeyResult {
                    HStack {
                        Text("Key Exists:")
                        Spacer()
                        Text(exists ? "YES" : "NO")
                            .fontWeight(.semibold)
                            .foregroundColor(exists ? .green : .secondary)
                    }
                }
            }

            // Retrieved Value Output
            if !viewModel.retrievedValue.isEmpty {
                Section(header: Text("Retrieved Value")) {
                    Text(viewModel.retrievedValue)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            // Codable Struct Section
            Section(header: Text("Codable Object Persistence")) {
                TextField("User ID", text: $viewModel.profileUserId)
                    .onChange(of: viewModel.profileUserId) { _ in viewModel.profileFieldsChanged() }
                TextField("Username", text: $viewModel.profileUsername)
                    .onChange(of: viewModel.profileUsername) { _ in viewModel.profileFieldsChanged() }
                TextField("Role", text: $viewModel.profileRole)
                    .onChange(of: viewModel.profileRole) { _ in viewModel.profileFieldsChanged() }

                HStack {
                    if viewModel.hasUnsavedProfileChanges {
                        Label("Unsaved changes", systemImage: "pencil.and.outline")
                            .foregroundColor(.orange)
                    } else if viewModel.isProfileStored {
                        Label("Saved", systemImage: "checkmark.seal.fill")
                            .foregroundColor(.green)
                    } else {
                        Label("Not saved yet", systemImage: "info.circle")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .font(.caption)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    Button(action: { viewModel.saveProfile() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .renderingMode(.template)
                            Text(viewModel.hasUnsavedProfileChanges ? "Save Changes" : "Save Profile")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: { viewModel.readProfile() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle")
                                .renderingMode(.template)
                            Text("Read Profile")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)

                if let feedback = viewModel.profileFeedback {
                    ProfileFeedbackBanner(feedback: feedback)
                }

                if let profile = viewModel.retrievedProfile {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Decoded Profile:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("ID: \(profile.userId)")
                        Text("Username: \(profile.username)")
                        Text("Role: \(profile.role)")
                        Text("Issued: \(profile.issuedAt.formatted())")
                    }
                    .font(.footnote)
                    .padding(.vertical, 4)
                }
            }

            // Raw Data Demonstration
            Section(header: Text("Raw Data Persistence")) {
                Button("Test Raw Data Storage (8 bytes)") {
                    viewModel.testDataPersistence()
                }
            }

            // Status & Feedback Section
            if !viewModel.statusMessage.isEmpty {
                Section(header: Text("Operation Feedback")) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: viewModel.isErrorMessage ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundColor(viewModel.isErrorMessage ? .red : .green)
                            .padding(.top, 2)
                        Text(viewModel.statusMessage)
                            .font(.footnote)
                            .foregroundColor(viewModel.isErrorMessage ? .red : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // Destructive Cleanup Section
            Section(header: Text("Batch Cleanup")) {
                Button(role: .destructive, action: { viewModel.clearAllStorage() }) {
                    Label("Remove All Items (removeAll)", systemImage: "trash.circle.fill")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Secure Storage")
    }
}

private struct ProfileFeedbackBanner: View {
    let feedback: SecureStorageFeedback

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundColor(tint)
                .padding(.top, 2)
            Text(feedback.message)
                .font(.footnote)
                .foregroundColor(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private var tint: Color {
        switch feedback.style {
        case .success: return .green
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var symbol: String {
        switch feedback.style {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}
