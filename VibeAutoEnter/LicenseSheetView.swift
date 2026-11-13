import SwiftUI

struct LicenseSheetView: View {
    @ObservedObject var licenseManager = LicenseManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var inputKey: String = ""
    @State private var showKeyInput: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding([.top, .trailing], 12)
            
            ScrollView {
                VStack(spacing: 16) {
                    // Header Icon & Title
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.purple.opacity(0.8), Color.indigo.opacity(0.9)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 54, height: 54)
                            
                            Image(systemName: "sparkles")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Text("VibeAutoEnter Pro")
                            .font(.title2.weight(.bold))
                        
                        tierBadge
                    }
                    .padding(.top, -10)
                    
                    // Features list
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(ProFeature.allCases, id: \.self) { feature in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: feature.icon)
                                    .font(.headline)
                                    .foregroundColor(.purple)
                                    .frame(width: 22)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                    Text(feature.description)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                    )
                    
                    // Status & Actions
                    if licenseManager.isPro && !isTrialActive {
                        // Already Pro Activated
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                Text("Pro License Active")
                                    .font(.subheadline.weight(.semibold))
                            }
                            if !licenseManager.customerEmail.isEmpty {
                                Text("Registered to: \(licenseManager.customerEmail)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Button("Deactivate This Mac") {
                                licenseManager.deactivateLicense()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.top, 4)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(10)
                    } else {
                        // Free or Trial: Offer Upgrade & Key Entry
                        VStack(spacing: 12) {
                            Button(action: {
                                NSWorkspace.shared.open(licenseManager.storeURL)
                            }) {
                                HStack {
                                    Image(systemName: "cart.fill")
                                    Text("Get Pro License — Lifetime ($19)")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .controlSize(.large)
                            
                            Divider()
                            
                            // License Key Entry Toggle
                            if !showKeyInput {
                                Button("Already purchased? Enter License Key") {
                                    showKeyInput = true
                                }
                                .font(.caption)
                                .foregroundColor(.accentColor)
                                .buttonStyle(.plain)
                            } else {
                                VStack(spacing: 8) {
                                    HStack {
                                        TextField("e.g. VIBE-PRO-XXXX or Gumroad Key", text: $inputKey)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.caption.monospaced())
                                        
                                        Button("Activate") {
                                            Task {
                                                let success = await licenseManager.activateLicense(key: inputKey)
                                                if success {
                                                    dismiss()
                                                }
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(inputKey.trimmingCharacters(in: .whitespaces).isEmpty || licenseManager.isValidating)
                                    }
                                    
                                    if licenseManager.isValidating {
                                        HStack(spacing: 6) {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Verifying with marketplace…")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    if let error = licenseManager.validationError {
                                        Text(error)
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                    }
                    
                    Text("Guaranteed 14-day refund • Works offline • 1 license for 2 Macs")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 380, height: 530)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var isTrialActive: Bool {
        if case .trial = licenseManager.tier {
            return true
        }
        return false
    }
    
    @ViewBuilder
    private var tierBadge: some View {
        switch licenseManager.tier {
        case .free:
            Text("Free Plan")
                .font(.caption.weight(.bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(6)
        case .trial(let days):
            Text("\(days) Days Left in Free Trial")
                .font(.caption.weight(.bold))
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(6)
        case .pro:
            Text("Pro Unlocked")
                .font(.caption.weight(.bold))
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.15))
                .cornerRadius(6)
        }
    }
}
