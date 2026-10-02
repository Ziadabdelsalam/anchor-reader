import SwiftUI

struct ResearchView: View {
    let asSheet: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app

    var body: some View {
        let ui = app.settings.ui
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Why these features")
                            .font(.system(size: ui * 1.8, weight: .bold))
                        Text("Every feature in Anchor is based on published research from universities and peer-reviewed journals. Where the evidence didn't hold up, the feature was left out.")
                            .font(.system(size: ui))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(ResearchContent.findings) { finding in
                        FindingCard(finding: finding, ui: ui)
                    }

                    Text("Left out on purpose")
                        .font(.system(size: ui * 1.4, weight: .bold))
                        .padding(.top, 8)
                    ForEach(ResearchContent.leftOut) { finding in
                        FindingCard(finding: finding, ui: ui)
                    }

                    Text("Habits that help with any document")
                        .font(.system(size: ui * 1.4, weight: .bold))
                        .padding(.top, 8)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(ResearchContent.tips, id: \.self) { tip in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(Color.accentColor)
                                Text(tip)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Link(ResearchContent.paperVsScreen.0, destination: URL(string: ResearchContent.paperVsScreen.1)!)
                            .font(.system(size: ui * 0.85))
                    }
                    .font(.system(size: ui))

                    Text("Anchor is a reading aid, not a medical treatment. If reading has become much harder than it used to be, it's worth talking to a doctor; attention, sleep, vision and stress can all play a part.")
                        .font(.system(size: ui * 0.85))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
                .padding(28)
            }
            if asSheet {
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.large)
                }
                .padding(16)
            }
        }
    }
}

struct FindingCard: View {
    let finding: Finding
    let ui: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: finding.icon)
                .font(.system(size: ui * 1.3))
                .foregroundStyle(Color.accentColor)
                .frame(width: ui * 2)
            VStack(alignment: .leading, spacing: 8) {
                Text(finding.feature)
                    .font(.system(size: ui * 1.1, weight: .semibold))
                Text(finding.evidence)
                    .font(.system(size: ui))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(finding.sources, id: \.1) { label, url in
                        if let link = URL(string: url) {
                            Link(destination: link) {
                                Label(label, systemImage: "link")
                                    .multilineTextAlignment(.leading)
                            }
                            .font(.system(size: ui * 0.82))
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(0.5)))
    }
}
