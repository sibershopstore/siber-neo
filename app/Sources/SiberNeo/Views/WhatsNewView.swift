import SwiftUI

/// Release notes shown once after the app is updated.
enum ReleaseNotes {
    struct Item: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    static let lastSeenKey = "whatsNewLastSeenVersion"

    static var items: [Item] {
        [
            Item(
                icon: "arrow.down.circle.fill",
                title: tr("Pembaruan otomatis", "Automatic updates"),
                detail: tr("Siber Neo kini memberi tahu saat versi baru tersedia di situs resmi, lengkap dengan tombol unduh di notch.",
                           "Siber Neo now tells you when a new version is available on the official site, with a download button right in the notch.")
            ),
            Item(
                icon: "figure.cooldown",
                title: tr("\(UserProfile.mascotName) menemani fokus", "\(UserProfile.mascotName) keeps you company"),
                detail: tr("Bekerja di depan laptop mini selama sesi fokus, lalu mengajak peregangan saat istirahat atau setelah 1 jam aktif.",
                           "Works at a tiny laptop during focus sessions, then invites you to stretch on breaks or after an hour of activity.")
            ),
            Item(
                icon: "birthday.cake.fill",
                title: tr("Ulang tahun dan nama maskot", "Birthday and mascot name"),
                detail: tr("Atur tanggal ulang tahun untuk perayaan dengan konfeti, dan beri nama maskot sesuai keinginan.",
                           "Set your birthday for a confetti celebration, and give the mascot a name of your choice.")
            ),
            Item(
                icon: "crown.fill",
                title: tr("Koleksi aksesori", "Accessory collection"),
                detail: tr("Kebiasaan baik membuka kacamata, bunga, topi wisuda, dan mahkota. Pakaian juga menyesuaikan cuaca dan musim.",
                           "Good habits unlock glasses, a flower, a graduation cap, and a crown. Outfits also follow the weather and seasons.")
            ),
            Item(
                icon: "sparkles",
                title: tr("Tampilan lebih hidup", "A livelier look"),
                detail: tr("Glow warna album, sampul yang berbalik saat ganti lagu, animasi pengisian daya, dan transisi tab yang halus.",
                           "Album-colored glow, artwork that flips between songs, a charging animation, and smooth tab transitions.")
            )
        ]
    }
}

struct WhatsNewView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                MascotView(size: 64, interactive: true)
                    .frame(width: 76, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Yang baru di Siber Neo \(UpdateService.currentVersion)", "What's new in Siber Neo \(UpdateService.currentVersion)"))
                        .font(.system(size: 20, weight: .bold))
                    Text(tr("Terima kasih telah memperbarui. Ini yang bisa dicoba sekarang.", "Thanks for updating. Here's what you can try now."))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.top, 36)
            .padding(.bottom, 18)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(ReleaseNotes.items) { item in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: item.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.red)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Theme.red.opacity(0.14)))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(item.detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
            }

            HStack {
                Spacer()
                Button(tr("Lanjutkan", "Continue"), action: onClose)
                    .buttonStyle(PillButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .frame(width: 600, height: 480)
        .background(
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.07, blue: 0.13), Color(red: 0.01, green: 0.02, blue: 0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
    }
}
