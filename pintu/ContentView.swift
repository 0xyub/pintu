//
//  ContentView.swift
//  pintu
//
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Model
struct CollageItem: Identifiable, Equatable {
    let id = UUID()
    var image: NSImage
}

@MainActor
final class CollageStore: ObservableObject {
    @Published var items: [CollageItem] = []

    func add(_ img: NSImage) { items.append(.init(image: img)) }
    func remove(at index: Int) { guard items.indices.contains(index) else { return }; items.remove(at: index) }
    func move(from: Int, to: Int) {
        guard from != to, items.indices.contains(from), (0...items.count).contains(to) else { return }
        let item = items.remove(at: from)
        items.insert(item, at: min(max(0, to), items.count))
    }
}

// MARK: - App (removed - using pintuApp.swift instead)

// MARK: - Root View
struct ContentView: View {
    @EnvironmentObject var store: CollageStore

    @State private var columns: Int = 0 // 0 means auto-columns
    @State private var isAutoColumns: Bool = true
    @State private var spacing: CGFloat = 12
    @State private var cornerRadius: CGFloat = 12
    @State private var borderWidth: CGFloat = 1
    @State private var canvasBG: Color = Color(.windowBackgroundColor)
    @State private var itemBG: Color = Color(.controlBackgroundColor)
    @State private var exportScale: CGFloat = 2
    @State private var showSettings = false

    // Computed property for effective columns (auto or manual)
    var effectiveColumns: Int {
        if isAutoColumns || columns == 0 {
            return calculateOptimalColumns(for: store.items.count)
        }
        return max(1, columns)
    }
    
    // Calculate optimal columns based on number of images
    private func calculateOptimalColumns(for itemCount: Int) -> Int {
        switch itemCount {
        case 0: return 1
        case 1: return 1
        case 2: return 2
        case 3: return 3
        case 4: return 2
        case 5...6: return 3
        case 7...9: return 3
        case 10...12: return 4
        case 13...16: return 4
        case 17...20: return 5
        default: return max(4, Int(sqrt(Double(itemCount)).rounded()))
        }
    }

    var body: some View {
        NavigationSplitView {
            ModernSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            VStack(spacing: 0) {
                ModernToolbar(columns: $columns, isAutoColumns: $isAutoColumns, effectiveColumns: effectiveColumns, spacing: $spacing, cornerRadius: $cornerRadius, borderWidth: $borderWidth, canvasBG: $canvasBG, itemBG: $itemBG, exportScale: $exportScale, showSettings: $showSettings)
                
                GeometryReader { geometry in
                    CollageCanvas(columns: effectiveColumns, spacing: spacing, cornerRadius: cornerRadius, borderWidth: borderWidth, canvasBG: canvasBG, itemBG: itemBG)
                        .environmentObject(store)
                        .overlay(
                            DropHintOverlay()
                                .opacity(store.items.isEmpty ? 1 : 0)
                                .animation(.easeInOut(duration: 0.3), value: store.items.isEmpty)
                        )
                        .onDrop(of: [UTType.image, UTType.fileURL, UTType.url], isTargeted: nil) { providers in
                            Task { await handleDrop(providers: providers) }
                            return true
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
            .background(Color(.windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .popover(isPresented: $showSettings, arrowEdge: .trailing) {
            SettingsView(columns: $columns, isAutoColumns: $isAutoColumns, effectiveColumns: effectiveColumns, spacing: $spacing, cornerRadius: $cornerRadius, borderWidth: $borderWidth, canvasBG: $canvasBG, itemBG: $itemBG, exportScale: $exportScale)
        }
    }

    // MARK: - Drop Handling
    func handleDrop(providers: [NSItemProvider]) async {
        for provider in providers {
            // 1) Direct image data
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                await withCheckedContinuation { continuation in
                    let _ = provider.loadDataRepresentation(for: .image) { data, error in
                        if let data = data, let img = NSImage(data: data) {
                            Task { @MainActor in
                                store.add(img)
                            }
                        }
                        continuation.resume()
                    }
                }
                continue
            }
            // 2) Local file URL
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                        if let urlData = item as? Data,
                           let url = URL(dataRepresentation: urlData, relativeTo: nil),
                           let img = NSImage(contentsOf: url) {
                            Task { @MainActor in
                                store.add(img)
                            }
                        }
                        continuation.resume()
                    }
                }
                continue
            }
            // 3) Remote URL (drag from Safari)
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                await withCheckedContinuation { continuation in
                    let _ = provider.loadDataRepresentation(for: .url) { urlData, error in
                        if let urlData = urlData,
                           let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                            Task {
                                do {
                                    let (data, _) = try await URLSession.shared.data(from: url)
                                    if let img = NSImage(data: data) {
                                        await MainActor.run {
                                            store.add(img)
                                        }
                                    }
                                } catch {
                                    // Ignore failures silently
                                }
                            }
                        }
                        continuation.resume()
                    }
                }
            }
        }
    }
}

// MARK: - Modern Toolbar
struct ModernToolbar: View {
    @EnvironmentObject var store: CollageStore
    @Binding var columns: Int
    @Binding var isAutoColumns: Bool
    let effectiveColumns: Int
    @Binding var spacing: CGFloat
    @Binding var cornerRadius: CGFloat
    @Binding var borderWidth: CGFloat
    @Binding var canvasBG: Color
    @Binding var itemBG: Color
    @Binding var exportScale: CGFloat
    @Binding var showSettings: Bool

    var body: some View {
        HStack {
            // App title with modern styling
            HStack(spacing: 8) {
                Image(systemName: "rectangle.3.group")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Pintu")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            
            Spacer()
            
            // Quick actions with modern design
            HStack(spacing: 12) {
                // Grid size control
                HStack(spacing: 6) {
                    Image(systemName: isAutoColumns ? "grid.circle" : "grid")
                        .font(.caption)
                        .foregroundStyle(isAutoColumns ? .blue : .secondary)
                    Text(isAutoColumns ? "Auto (\(effectiveColumns))" : "\(effectiveColumns)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .frame(minWidth: 40)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .onTapGesture { showSettings = true }
                
                Divider()
                    .frame(height: 20)
                
                // Primary actions
                Button {
                    NSOpenPanel.pickImages { images in 
                        images.forEach { store.add($0) } 
                    }
                } label: {
                    Label("Add Images", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                
                Button(role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        store.items.removeAll()
                    }
                } label: {
                    Label("Clear All", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(store.items.isEmpty)
                
                Menu {
                    Button("Export PNG (1x)") { export(scale: 1) }
                    Button("Export PNG (2x)") { export(scale: 2) }
                    Button("Export PNG (4x)") { export(scale: 4) }
                    Divider()
                    Button("Export JPEG (High Quality)") { exportJPEG(quality: 0.9) }
                    Button("Export JPEG (Medium Quality)") { exportJPEG(quality: 0.7) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                        .labelStyle(.iconOnly)
                } primaryAction: {
                    export(scale: exportScale)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.items.isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    func export(scale: CGFloat) {
        // Calculate export size based on number of items and desired quality
        let baseImageSize: CGFloat = 512 // Base size per image in points
        let exportSize = calculateExportSize(baseImageSize: baseImageSize)
        
        let view = CollageExportView(
            store: store, 
            columns: effectiveColumns, 
            spacing: spacing, 
            cornerRadius: cornerRadius, 
            borderWidth: borderWidth, 
            canvasBG: canvasBG, 
            itemBG: itemBG, 
            exportSize: exportSize
        )
        
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        
        // Ensure we get a good quality image
        if let nsImage = renderer.nsImage { 
            print("Export size: \(nsImage.size), scale: \(scale)")
            NSSavePanel.save(nsImage: nsImage, format: .png) 
        } else {
            print("Failed to render image")
        }
    }
    
    func exportJPEG(quality: CGFloat) {
        // Use slightly larger base size for JPEG to compensate for compression
        let baseImageSize: CGFloat = 640
        let exportSize = calculateExportSize(baseImageSize: baseImageSize)
        
        let view = CollageExportView(
            store: store, 
            columns: effectiveColumns, 
            spacing: spacing, 
            cornerRadius: cornerRadius, 
            borderWidth: borderWidth, 
            canvasBG: canvasBG, 
            itemBG: itemBG, 
            exportSize: exportSize
        )
        
        let renderer = ImageRenderer(content: view)
        renderer.scale = exportScale
        
        if let nsImage = renderer.nsImage { 
            print("Export JPEG size: \(nsImage.size), scale: \(exportScale)")
            NSSavePanel.save(nsImage: nsImage, format: .jpeg, quality: quality) 
        } else {
            print("Failed to render JPEG")
        }
    }
    
    private func calculateExportSize(baseImageSize: CGFloat) -> CGSize {
        // Calculate optimal export size based on grid layout
        let cols = effectiveColumns
        let rows = (store.items.count + cols - 1) / cols
        let totalSpacing = spacing * CGFloat(cols + 1)
        let totalHeight = spacing * CGFloat(rows + 1)
        
        let width = (baseImageSize * CGFloat(cols)) + totalSpacing
        let height = (baseImageSize * CGFloat(rows)) + totalHeight
        
        return CGSize(width: max(width, 400), height: max(height, 300))
    }
}

// MARK: - Export View (for ImageRenderer)
struct CollageExportView: View {
    let store: CollageStore
    let columns: Int
    let spacing: CGFloat
    let cornerRadius: CGFloat
    let borderWidth: CGFloat
    let canvasBG: Color
    let itemBG: Color
    let exportSize: CGSize
    
    var body: some View {
        VStack(spacing: 0) {
            if store.items.isEmpty {
                // Empty state for export
                Rectangle()
                    .fill(canvasBG)
                    .frame(width: exportSize.width, height: exportSize.height)
                    .overlay(
                        Text("No Images")
                            .foregroundColor(.secondary)
                            .font(.system(size: 48))
                    )
            } else {
                // Create a grid manually using VStack and HStack for reliable rendering
                let items = store.items
                let rows = (items.count + columns - 1) / columns // Calculate number of rows
                
                // Calculate the size for each image card
                let totalSpacing = spacing * CGFloat(columns + 1) // spacing around and between items
                let availableWidth = exportSize.width - totalSpacing
                let cardSize = availableWidth / CGFloat(columns)
                
                VStack(spacing: spacing) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<columns, id: \.self) { col in
                                let index = row * columns + col
                                if index < items.count {
                                    ExportCard(
                                        item: items[index], 
                                        cornerRadius: cornerRadius, 
                                        borderWidth: borderWidth, 
                                        itemBG: itemBG,
                                        cardSize: cardSize
                                    )
                                } else {
                                    // Empty space for incomplete rows
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(width: cardSize, height: cardSize)
                                }
                            }
                        }
                    }
                }
                .padding(spacing)
                .background(canvasBG)
            }
        }
        .frame(width: exportSize.width, height: exportSize.height)
    }
}

// MARK: - Export Card (simplified for rendering)
struct ExportCard: View {
    let item: CollageItem
    let cornerRadius: CGFloat
    let borderWidth: CGFloat
    let itemBG: Color
    let cardSize: CGFloat
    
    var body: some View {
        Image(nsImage: item.image)
            .resizable()
            .scaledToFill()
            .frame(width: cardSize, height: cardSize)
            .clipped()
            .background(itemBG)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderWidth > 0 ? Color.primary.opacity(0.2) : Color.clear, lineWidth: borderWidth)
            )
    }
}

// MARK: - Canvas
struct CollageCanvas: View {
    @EnvironmentObject var store: CollageStore

    var columns: Int
    var spacing: CGFloat
    var cornerRadius: CGFloat
    var borderWidth: CGFloat
    var canvasBG: Color
    var itemBG: Color
    @State private var targetIndex: Int?

    var grid: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: spacing), count: max(1, columns)) }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: grid, spacing: spacing) {
                ForEach(Array(store.items.enumerated()), id: \.1.id) { index, item in
                    CollageCard(item: item, index: index, cornerRadius: cornerRadius, borderWidth: borderWidth, itemBG: itemBG)
                        .contextMenu { contextMenu(for: index) }
                        .scaleEffect(targetIndex == index ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: targetIndex)
                        .dropDestination(for: String.self) { draggedItemIds, location in
                            // Handle drop to reorder
                            targetIndex = nil
                            if let draggedItemId = draggedItemIds.first,
                               let draggedIndex = store.items.firstIndex(where: { $0.id.uuidString == draggedItemId }) {
                                if draggedIndex != index {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        store.move(from: draggedIndex, to: index)
                                    }
                                }
                                return true
                            }
                            return false
                        } isTargeted: { isTargeted in
                            targetIndex = isTargeted ? index : nil
                        }
                }
            }
            .padding(spacing)
        }
        .background(canvasBG)
    }

    @ViewBuilder
    private func contextMenu(for index: Int) -> some View {
        Button("上移") { store.move(from: index, to: max(0, index - 1)) }
        Button("下移") { store.move(from: index, to: min(store.items.count, index + 1)) }
        Divider()
        Button("删除", role: .destructive) { store.remove(at: index) }
    }
}

struct CollageCard: View {
    let item: CollageItem
    let index: Int
    let cornerRadius: CGFloat
    let borderWidth: CGFloat
    let itemBG: Color
    @State private var isHovered = false
    @State private var isDragging = false
    @EnvironmentObject var store: CollageStore

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Image(nsImage: item.image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .background(itemBG)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(borderWidth > 0 ? Color.primary.opacity(0.2) : Color.clear, lineWidth: borderWidth)
                )
                .overlay(alignment: .bottomLeading) {
                    // Index number badge
                    Text("\(index + 1)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.7), in: Capsule())
                        .padding(8)
                        .opacity(isHovered ? 1 : 0.7)
                        .animation(.easeInOut(duration: 0.2), value: isHovered)
                }
                .overlay(alignment: .topTrailing) {
                    // Simple remove button
                    Button {
                        deleteSelf()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .background(.red.opacity(0.8), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .opacity(isHovered ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
                }
                .overlay(alignment: .center) {
                    // Drag indicator when hovering
                    if isHovered && !isDragging {
                        Image(systemName: "move.3d")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .opacity(0.8)
                            .animation(.easeInOut(duration: 0.2), value: isHovered)
                    }
                }
                .scaleEffect(isDragging ? 1.05 : isHovered ? 0.98 : 1.0)
                .shadow(color: .black.opacity(isDragging ? 0.4 : isHovered ? 0.3 : 0.1), 
                       radius: isDragging ? 12 : isHovered ? 8 : 4, x: 0, y: 2)
                .animation(.easeInOut(duration: 0.2), value: isHovered)
                .animation(.easeInOut(duration: 0.2), value: isDragging)
                .onHover { hovering in
                    isHovered = hovering
                }
        }
        .aspectRatio(1, contentMode: .fit)
        .draggable(item.id.uuidString) {
            // Drag preview
            Image(nsImage: item.image)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .onDrag {
            isDragging = true
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
        .onChange(of: isDragging) { _, newValue in
            if !newValue {
                // Reset drag state after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isDragging = false
                }
            }
        }
    }

    private func deleteSelf() {
        withAnimation(.easeInOut(duration: 0.3)) {
            store.remove(at: index)
        }
    }
}

// MARK: - Helper Types for Actions
struct MoveFromToContext {
    let from: Int
    let to: Int
}

// MARK: - Actions via NSResponder chain (so ContextMenu can trigger)
protocol AppActions {
    func deleteItem()
    func moveUp()
    func moveDown()
    func moveTop()
    func moveBottom()
    func moveFromTo()
}

extension NSResponder {
    @objc func deleteItem() {}
    @objc func moveItemUp() {}
    @objc func moveItemDown() {}
    @objc func moveItemTop() {}
    @objc func moveItemBottom() {}
    @objc func moveItemFromTo() {}
}

// MARK: - Modern Sidebar
struct ModernSidebar: View {
    @EnvironmentObject var store: CollageStore
    @State private var selectedIndices = Set<Int>()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if store.items.isEmpty {
                    ContentUnavailableView(
                        "No Images",
                        systemImage: "photo.on.rectangle",
                        description: Text("Add images by dropping them onto the canvas or using the + button")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedIndices) {
                        Section {
                            ForEach(Array(store.items.enumerated()), id: \.offset) { index, item in
                                ImageRowView(item: item, index: index)
                                    .tag(index)
                                    .contextMenu {
                                        Button("Move to Top") { 
                                            withAnimation { store.move(from: index, to: 0) }
                                        }
                                        Button("Move to Bottom") { 
                                            withAnimation { store.move(from: index, to: store.items.count - 1) }
                                        }
                                        Divider()
                                        Button("Remove", role: .destructive) { 
                                            withAnimation { store.remove(at: index) }
                                        }
                                    }
                            }
                            .onMove { source, destination in
                                withAnimation {
                                    for index in source {
                                        store.move(from: index, to: destination)
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text("Images (\(store.items.count))")
                                Spacer()
                                if !store.items.isEmpty {
                                    Button("Clear All", role: .destructive) {
                                        withAnimation {
                                            store.items.removeAll()
                                        }
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .navigationTitle("Layers")
        }
    }
}

// MARK: - Image Row View
struct ImageRowView: View {
    let item: CollageItem
    let index: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            AsyncImage(url: nil) { _ in
                Image(nsImage: item.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 40, height: 40)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Image \(index + 1)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(Int(item.image.size.width))×\(Int(item.image.size.height))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text("#\(index + 1)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @Binding var columns: Int
    @Binding var isAutoColumns: Bool
    let effectiveColumns: Int
    @Binding var spacing: CGFloat
    @Binding var cornerRadius: CGFloat
    @Binding var borderWidth: CGFloat
    @Binding var canvasBG: Color
    @Binding var itemBG: Color
    @Binding var exportScale: CGFloat
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Layout") {
                    VStack(spacing: 16) {
                        // Auto columns toggle
                        HStack(spacing: 12) {
                            Label("Auto Columns", systemImage: "grid.circle")
                                .font(.body)
                            Spacer()
                            Toggle("", isOn: $isAutoColumns)
                                .labelsHidden()
                                .onChange(of: isAutoColumns) { _, newValue in
                                    if !newValue && columns == 0 {
                                        columns = 3 // Set default when switching to manual
                                    }
                                }
                        }
                        .padding(.vertical, 4)
                        
                        // Stable container with fixed height for consistent layout
                        HStack(spacing: 12) {
                            Label(isAutoColumns ? "Current Layout" : "Manual Columns", 
                                 systemImage: isAutoColumns ? "info.circle" : "grid")
                                .foregroundStyle(isAutoColumns ? .secondary : .primary)
                                .font(.body)
                            Spacer()
                            
                            // Use a single container that changes content without changing structure
                            HStack {
                                if isAutoColumns {
                                    Text("\(effectiveColumns) columns")
                                        .foregroundStyle(.secondary)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .transition(.asymmetric(
                                            insertion: .opacity.combined(with: .scale(scale: 0.8)),
                                            removal: .opacity.combined(with: .scale(scale: 0.8))
                                        ))
                                } else {
                                    Stepper("\(columns == 0 ? 3 : columns)", value: Binding(
                                        get: { columns == 0 ? 3 : columns },
                                        set: { columns = $0 }
                                    ), in: 1...12)
                                        .fixedSize()
                                        .transition(.asymmetric(
                                            insertion: .opacity.combined(with: .scale(scale: 0.8)),
                                            removal: .opacity.combined(with: .scale(scale: 0.8))
                                        ))
                                        .onAppear {
                                            if columns == 0 && !isAutoColumns {
                                                columns = 3 // Set default when switching to manual
                                            }
                                        }
                                }
                            }
                            .frame(minWidth: 120, alignment: .trailing) // Fixed width prevents layout shift
                        }
                        .padding(.vertical, 4)
                        .frame(minHeight: 44) // Consistent minimum height
                        .animation(.easeInOut(duration: 0.25), value: isAutoColumns)
                    }
                    .padding(.vertical, 8)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Label("Spacing", systemImage: "arrow.left.and.right")
                                .font(.body)
                            Spacer()
                            Text("\(Int(spacing))px")
                                .foregroundStyle(.secondary)
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 4)
                        Slider(value: $spacing, in: 0...40, step: 1)
                            .padding(.horizontal, 4)
                    }
                    .padding(.vertical, 8)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Label("Corner Radius", systemImage: "rectangle.roundedbottom")
                                .font(.body)
                            Spacer()
                            Text("\(Int(cornerRadius))px")
                                .foregroundStyle(.secondary)
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 4)
                        Slider(value: $cornerRadius, in: 0...40, step: 1)
                            .padding(.horizontal, 4)
                    }
                    .padding(.vertical, 8)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Label("Border Width", systemImage: "rectangle.portrait")
                                .font(.body)
                            Spacer()
                            Text("\(Int(borderWidth))px")
                                .foregroundStyle(.secondary)
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 4)
                        Slider(value: $borderWidth, in: 0...8, step: 0.5)
                            .padding(.horizontal, 4)
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Colors") {
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Label("Canvas Background", systemImage: "rectangle")
                                .font(.body)
                            Spacer()
                            ColorPicker("", selection: $canvasBG)
                                .labelsHidden()
                                .frame(width: 44, height: 32)
                        }
                        .padding(.vertical, 4)
                        
                        HStack(spacing: 12) {
                            Label("Image Background", systemImage: "photo")
                                .font(.body)
                            Spacer()
                            ColorPicker("", selection: $itemBG)
                                .labelsHidden()
                                .frame(width: 44, height: 32)
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Export") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Label("Default Scale", systemImage: "square.and.arrow.down")
                                .font(.body)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        
                        Picker("Default Scale", selection: $exportScale) {
                            Text("1x").tag(1.0)
                            Text("2x").tag(2.0)
                            Text("4x").tag(4.0)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 4)
                    }
                    .padding(.vertical, 8)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 500)
        .animation(.easeInOut(duration: 0.2), value: isAutoColumns)
    }
}

// MARK: - UI Helpers
struct DropHintOverlay: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(.blue.opacity(0.8))
            
            VStack(spacing: 8) {
                Text("Drop Images Here")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                
                Text("Drag images from Finder, Safari, or other apps")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .foregroundStyle(.blue)
                    Text("Multiple\nImages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 4) {
                    Image(systemName: "network")
                        .font(.title3)
                        .foregroundStyle(.green)
                    Text("Web\nImages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    Text("Local\nFiles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 8)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.quaternary, lineWidth: 1, antialiased: true)
                )
        )
        .scaleEffect(0.9)
    }
}

// MARK: - Panels
extension NSOpenPanel {
    static func pickImages(completion: @escaping ([NSImage]) -> Void) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = true
        p.begin { resp in
            guard resp == .OK else { return }
            let imgs: [NSImage] = p.urls.compactMap { NSImage(contentsOf: $0) }
            completion(imgs)
        }
    }
}

extension NSSavePanel {
    enum ImageFormat {
        case png, jpeg
    }
    
    static func save(nsImage: NSImage, format: ImageFormat = .png, quality: CGFloat = 1.0) {
        DispatchQueue.main.async {
            let p = NSSavePanel()
            
            switch format {
            case .png:
                p.allowedContentTypes = [.png]
                p.nameFieldStringValue = "collage.png"
            case .jpeg:
                p.allowedContentTypes = [.jpeg]
                p.nameFieldStringValue = "collage.jpg"
            }
            
            p.canCreateDirectories = true
            p.showsResizeIndicator = true
            p.showsHiddenFiles = false
            p.isExtensionHidden = false
            
            p.begin { resp in
                guard resp == .OK, let url = p.url else { 
                    print("Save cancelled or failed")
                    return 
                }
                
                do {
                    guard let tiff = nsImage.tiffRepresentation, 
                          let rep = NSBitmapImageRep(data: tiff) else { 
                        print("Failed to create image representation")
                        return 
                    }
                    
                    let data: Data?
                    switch format {
                    case .png:
                        data = rep.representation(using: .png, properties: [:])
                    case .jpeg:
                        data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
                    }
                    
                    guard let imageData = data else { 
                        print("Failed to generate image data")
                        return 
                    }
                    
                    try imageData.write(to: url)
                    print("Successfully saved image to: \(url.path)")
                    
                    // Show success notification
                    let notification = NSUserNotification()
                    notification.title = "Export Successful"
                    notification.informativeText = "Collage saved to \(url.lastPathComponent)"
                    NSUserNotificationCenter.default.deliver(notification)
                    
                } catch {
                    print("Error saving file: \(error)")
                    
                    // Show error alert
                    let alert = NSAlert()
                    alert.messageText = "Export Failed"
                    alert.informativeText = "Could not save the collage: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
}



