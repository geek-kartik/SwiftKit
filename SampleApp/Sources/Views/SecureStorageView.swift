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
                TextField("Username", text: $viewModel.profileUsername)
                TextField("Role", text: $viewModel.profileRole)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    Button(action: { viewModel.saveProfile() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .renderingMode(.template)
                            Text("Save Profile")
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
