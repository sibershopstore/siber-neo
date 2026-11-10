import AppKit
import SwiftUI

struct ShelfTabView: View {
    @EnvironmentObject var shelf: ShelfStore
    @EnvironmentObject var clipboard: ClipboardStore
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var preferences: AppPreferences

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(text: tr("Shelf · \(shelf.items.count) item", "Shelf · \(shelf.items.count) items"))
                    Spacer()
                    Button(preferences.screenshotShelf ? tr("Screenshot otomatis", "Auto screenshots") : tr("Screenshot manual", "Manual screenshots")) {
                        preferences.screenshotShelf.toggle()
                    }
                    .buttonStyle(ChipStyle(selected: preferences.screenshotShelf))
                    .help(tr("Masukkan setiap screenshot baru ke Shelf secara otomatis", "Automatically add every new screenshot to the Shelf"))
                    if !shelf.items.isEmpty {
                        Button(tr("Kosongkan", "Clear")) { shelf.clear() }
                            .buttonStyle(ChipStyle())
                    }
                }

                if shelf.items.isEmpty {
                    dropZone
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(shelf.items) { item in
                                ShelfTile(item: item)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Text(tr("Tarik keluar untuk memindahkan, klik untuk membuka.", "Drag out to move, click to open."))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Rectangle()
                .fill(Theme.stroke)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(text: "Clipboard")
                    Spacer()
                    if !clipboard.items.isEmpty {
                        Button(tr("Hapus", "Clear")) { clipboard.clear() }
                            .buttonStyle(ChipStyle())
                    }
                }
                if clipboard.items.isEmpty {
                    EmptyStateView(icon: "doc.on.clipboard", title: tr("Belum ada salinan", "Nothing copied yet"))
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(clipboard.items) { item in
                                ClipRow(item: item)
                            }
                        }
                    }
                }
            }
            .frame(width: 220, alignment: .topLeading)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 20))
                .foregroundStyle(state.isDropTargeted ? Theme.red : Theme.tertiary)
            Text(state.isDropTargeted ? tr("Lepaskan untuk menambahkan", "Drop to add") : tr("Tarik file ke sini", "Drag files here"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    state.isDropTargeted ? Theme.red : Color.white.opacity(0.14),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
    }
}

struct ShelfTile: View {
    @EnvironmentObject var shelf: ShelfStore
    let item: ShelfItem

    @StateObject var flags = ViewFlags()

    var body: some View {
        VStack(spacing: 6) {
            if let thumbnail = shelf.thumbnails[item.path] {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 54, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                    .resizable()
                    .frame(width: 46, height: 46)
            }
            Text(item.name)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(Theme.secondary)
        }
        .frame(width: 78, height: 84)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(flags.hovering ? Color.white.opacity(0.07) : Theme.card)
        )
        .onHover { flags.hovering = $0 }
        .onTapGesture {
            NSWorkspace.shared.open(item.url)
        }
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .contextMenu {
            Button(tr("Tampilkan di Finder", "Show in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button(tr("Hapus dari Shelf", "Remove from Shelf")) {
                shelf.remove(item.id)
            }
        }
    }
}

struct ClipRow: View {
    @EnvironmentObject var clipboard: ClipboardStore
    let item: ClipItem

    @StateObject var flags = ViewFlags()

    var body: some View {
        HStack(spacing: 8) {
            Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Color.white.opacity(0.85))
            Spacer(minLength: 4)
            Image(systemName: flags.copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundStyle(flags.copied ? Theme.red : Theme.tertiary)
                .opacity(flags.hovering || flags.copied ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(flags.hovering ? Color.white.opacity(0.07) : Theme.card)
        )
        .contentShape(Rectangle())
        .onHover { flags.hovering = $0 }
        .onTapGesture {
            clipboard.copy(item)
            flags.copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                flags.copied = false
            }
        }
        .onDrag {
            NSItemProvider(object: item.text as NSString)
        }
    }
}
