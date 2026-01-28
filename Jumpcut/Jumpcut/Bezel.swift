//
//  Bezel.swift
//  Jumpcut
//
//  Created by Steve Cook on 9/13/20.
//

import Cocoa

public struct BezelAppearance {
    let bezelSize: CGSize
    let outletSize: CGSize
    let secondaryOutletSize: CGSize?
    let windowAlpha: Double
    let windowAttributes: AppearanceAttributes
    let mainOutletAttributes: AppearanceAttributes
    let secondaryOutletAttributes: AppearanceAttributes?
    let outletFontColor: NSColor
}

public struct AppearanceAttributes {
    let backgroundColor: NSColor
    let borderWidth: Double
    let borderColor: NSColor
    let cornerRadius: Double
}

public class Bezel: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {

    let window: KeyCaptureWindow
    var shown: Bool = false
    private var hasBeenOpened = false

    fileprivate var mainOutlet: Outlet
    fileprivate var secondaryOutlet: Outlet? // Used for display of stack number

    // Search UI
    public var stack: ClippingStack?
    private var searchButton: NSButton!
    private var searchField: NSTextField!
    private var headerStackView: NSStackView!
    private var resultsScrollView: NSScrollView!
    private var resultsTableView: NSTableView!
    private var searchResults: [Clipping] = []
    private var isSearching: Bool = false
    public var onSelect: ((Clipping) -> Void)?
    
    // Timestamp UI
    private var timestampLabel: NSTextField!
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    // Preview UI
    private var previewScrollView: NSScrollView!
    private var previewTextView: NSTextView!
    
    // TODO: Add controls for positioning on window -- NB, not part of BezelAppearance
    //      -- Center, Top Left, Top Right, Top Center, Bottom Center
    // TODO: Add controls for positioning main outlet, secondary outlet
    // TODO: Add controls for changing the appearance

    static let defaultAppearance = BezelAppearance(
        bezelSize: CGSize(width: 325, height: 325),
        outletSize: CGSize(width: 300, height: 200),
        secondaryOutletSize: CGSize(width: 36, height: 30),
        windowAlpha: 0.8,
        windowAttributes: AppearanceAttributes(
            backgroundColor: NSColor.init(calibratedWhite: 0.1, alpha: 0.6),
            borderWidth: 0.0,
            borderColor: .clear,
            cornerRadius: 25.0
        ),
        mainOutletAttributes: AppearanceAttributes(
            backgroundColor: NSColor.init(calibratedWhite: 0.1, alpha: 0.9),
            borderWidth: 1.0,
            borderColor: .black,
            cornerRadius: 12.0
        ),
        secondaryOutletAttributes: AppearanceAttributes(
            backgroundColor: NSColor.init(calibratedWhite: 0.1, alpha: 0.9),
            borderWidth: 1.0,
            borderColor: .black,
            cornerRadius: 12.0
        ),
        outletFontColor: .white
    )

    fileprivate static func makeOutlet(size: CGSize, attributes: AppearanceAttributes) -> Outlet {
        return Outlet(
            width: size.width,
            height: size.height,
            backgroundColor: attributes.backgroundColor,
            cornerRadius: attributes.cornerRadius,
            borderWidth: attributes.borderWidth,
            borderColor: attributes.borderColor
        )
    }

    override public init() {
        let appearance = Bezel.defaultAppearance
        window = KeyCaptureWindow(contentRect: NSRect(origin: .zero, size: appearance.bezelSize),
                                  styleMask: .borderless, backing: .buffered, defer: true)
        mainOutlet = Bezel.makeOutlet(size: appearance.outletSize, attributes: appearance.mainOutletAttributes)
        if let secondarySize = appearance.secondaryOutletSize {
            var outletAttributes: AppearanceAttributes
            if appearance.secondaryOutletAttributes != nil {
                outletAttributes = appearance.secondaryOutletAttributes!
            } else {
                outletAttributes = appearance.mainOutletAttributes
            }
            secondaryOutlet = Bezel.makeOutlet(size: secondarySize, attributes: outletAttributes)
        } else {
            secondaryOutlet = nil
        }
        
        super.init()
        
        buildWindow(
            windowAlpha: appearance.windowAlpha,
            windowBackgroundColor: appearance.windowAttributes.backgroundColor,
            windowCornerRadius: appearance.windowAttributes.cornerRadius
        )

        // Timestamp UI
        timestampLabel = NSTextField()
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        timestampLabel.isEditable = false
        timestampLabel.isSelectable = false
        timestampLabel.isBordered = false
        timestampLabel.backgroundColor = .clear
        timestampLabel.textColor = Bezel.defaultAppearance.outletFontColor.withAlphaComponent(0.6)
        timestampLabel.font = NSFont.systemFont(ofSize: 10)
        timestampLabel.alignment = .right
        
        setupSearchUI()
        setupPreviewUI()

        window.contentView!.addSubview(mainOutlet.embedderView)
        window.contentView!.addSubview(timestampLabel)
        
        if let headerStackView = headerStackView {
            window.contentView!.addSubview(headerStackView)
        }
        
        // Add results view
        window.contentView!.addSubview(resultsScrollView)
        window.contentView!.addSubview(previewScrollView)

        var constraints = [
            mainOutlet.embedderView.widthAnchor.constraint(equalToConstant: appearance.outletSize.width),
            mainOutlet.embedderView.heightAnchor.constraint(equalToConstant: appearance.outletSize.height),
            mainOutlet.embedderView.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
            // Adjust main outlet to make room for timestamp
            mainOutlet.embedderView.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20),
            
            // Timestamp constraints
            timestampLabel.trailingAnchor.constraint(equalTo: mainOutlet.embedderView.trailingAnchor),
            timestampLabel.topAnchor.constraint(equalTo: mainOutlet.embedderView.bottomAnchor, constant: 2),
            timestampLabel.heightAnchor.constraint(equalToConstant: 15)
        ]
        
        if let headerStackView = headerStackView {
            constraints.append(contentsOf: [
                headerStackView.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
                headerStackView.bottomAnchor.constraint(equalTo: mainOutlet.embedderView.topAnchor, constant: -10),
                headerStackView.heightAnchor.constraint(equalToConstant: appearance.secondaryOutletSize?.height ?? 30)
            ])
        }
        
        // Results View Constraints (matches main outlet initially)
        constraints.append(contentsOf: [
            resultsScrollView.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 12),
            resultsScrollView.widthAnchor.constraint(equalToConstant: appearance.outletSize.width),
            resultsScrollView.topAnchor.constraint(equalTo: mainOutlet.embedderView.topAnchor),
            resultsScrollView.bottomAnchor.constraint(equalTo: mainOutlet.embedderView.bottomAnchor)
        ])
        
        // Preview View Constraints
        constraints.append(contentsOf: [
            previewScrollView.leadingAnchor.constraint(equalTo: resultsScrollView.trailingAnchor, constant: 10),
            previewScrollView.widthAnchor.constraint(equalToConstant: appearance.outletSize.width),
            previewScrollView.topAnchor.constraint(equalTo: resultsScrollView.topAnchor),
            previewScrollView.bottomAnchor.constraint(equalTo: resultsScrollView.bottomAnchor)
        ])

        NSLayoutConstraint.activate(constraints)
    }

    private func setupPreviewUI() {
        previewTextView = NSTextView()
        previewTextView.isEditable = false
        previewTextView.isSelectable = true
        previewTextView.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.9)
        previewTextView.textColor = .white
        previewTextView.font = NSFont.systemFont(ofSize: 14)
        previewTextView.textContainerInset = NSSize(width: 5, height: 5)
        
        previewScrollView = NSScrollView()
        previewScrollView.translatesAutoresizingMaskIntoConstraints = false
        previewScrollView.documentView = previewTextView
        previewScrollView.hasVerticalScroller = true
        previewScrollView.drawsBackground = false
        previewScrollView.isHidden = true
        
        previewScrollView.wantsLayer = true
        previewScrollView.layer?.cornerRadius = Bezel.defaultAppearance.mainOutletAttributes.cornerRadius
        previewScrollView.layer?.masksToBounds = true
        previewScrollView.layer?.borderWidth = Bezel.defaultAppearance.mainOutletAttributes.borderWidth
        previewScrollView.layer?.borderColor = Bezel.defaultAppearance.mainOutletAttributes.borderColor.cgColor
    }

    private func setupSearchUI() {
        // Search Button
        searchButton = NSButton()
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        searchButton.bezelStyle = .inline
        searchButton.isBordered = false
        if #available(OSX 10.12, *) {
             searchButton.image = NSImage(named: NSImage.touchBarSearchTemplateName)
        } else {
             searchButton.title = "🔍"
        }
        searchButton.target = self
        searchButton.action = #selector(toggleSearch)
        searchButton.widthAnchor.constraint(equalToConstant: 20).isActive = true
        searchButton.heightAnchor.constraint(equalToConstant: 20).isActive = true
        
        // Search Field
        searchField = NSTextField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.isHidden = true
        searchField.delegate = self
        searchField.focusRingType = .none
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        searchField.placeholderString = "Search..."
        
        // Header Stack View
        headerStackView = NSStackView()
        headerStackView.translatesAutoresizingMaskIntoConstraints = false
        headerStackView.orientation = .horizontal
        headerStackView.spacing = 8
        headerStackView.alignment = .centerY
        
        if let secondaryOutlet = secondaryOutlet {
            let appearance = Bezel.defaultAppearance
            if let size = appearance.secondaryOutletSize {
                secondaryOutlet.embedderView.widthAnchor.constraint(equalToConstant: size.width).isActive = true
                secondaryOutlet.embedderView.heightAnchor.constraint(equalToConstant: size.height).isActive = true
            }
            headerStackView.addArrangedSubview(secondaryOutlet.embedderView)
        }
        
        headerStackView.addArrangedSubview(searchButton)
        headerStackView.addArrangedSubview(searchField)
        
        // Results Table View
        resultsTableView = NSTableView()
        resultsTableView.headerView = nil
        resultsTableView.dataSource = self
        resultsTableView.delegate = self
        resultsTableView.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.9)
        resultsTableView.rowHeight = 24
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ResultColumn"))
        column.width = Bezel.defaultAppearance.outletSize.width
        resultsTableView.addTableColumn(column)
        
        resultsScrollView = NSScrollView()
        resultsScrollView.translatesAutoresizingMaskIntoConstraints = false
        resultsScrollView.documentView = resultsTableView
        resultsScrollView.hasVerticalScroller = true
        resultsScrollView.drawsBackground = false
        resultsScrollView.isHidden = true
        
        resultsScrollView.wantsLayer = true
        resultsScrollView.layer?.cornerRadius = Bezel.defaultAppearance.mainOutletAttributes.cornerRadius
        resultsScrollView.layer?.masksToBounds = true
        resultsScrollView.layer?.borderWidth = Bezel.defaultAppearance.mainOutletAttributes.borderWidth
        resultsScrollView.layer?.borderColor = Bezel.defaultAppearance.mainOutletAttributes.borderColor.cgColor
    }

    @objc private func toggleSearch() {
        isSearching = !isSearching
        searchField.isHidden = !isSearching
        
        if #available(OSX 10.12, *) {
            searchButton.image = isSearching ? NSImage(named: NSImage.touchBarIconViewTemplateName) : NSImage(named: NSImage.touchBarSearchTemplateName)
        }
        
        if isSearching {
            resultsScrollView.isHidden = false
            previewScrollView.isHidden = false
            mainOutlet.embedderView.isHidden = true
            
            // Resize window for split view
            let appearance = Bezel.defaultAppearance
            let newWidth = appearance.bezelSize.width * 2 // Double the width
            setWindowSize(size: CGSize(width: newWidth, height: appearance.bezelSize.height))
            window.center() // Recenter window
            
            window.makeFirstResponder(searchField)
            filterResults(query: searchField.stringValue)
        } else {
            resultsScrollView.isHidden = true
            previewScrollView.isHidden = true
            mainOutlet.embedderView.isHidden = false
            
            // Restore window size
            let appearance = Bezel.defaultAppearance
            setWindowSize(size: appearance.bezelSize)
            window.center()
            
            searchField.stringValue = ""
            window.makeFirstResponder(window)
        }
    }
    
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control == searchField else { return false }
        
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            let row = resultsTableView.selectedRow
            let nextRow = row + 1
            if nextRow < searchResults.count {
                resultsTableView.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
                resultsTableView.scrollRowToVisible(nextRow)
            } else if row == -1 && searchResults.count > 0 {
                resultsTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                resultsTableView.scrollRowToVisible(0)
            }
            return true
        } else if commandSelector == #selector(NSResponder.moveUp(_:)) {
            let row = resultsTableView.selectedRow
            let prevRow = row - 1
            if prevRow >= 0 {
                resultsTableView.selectRowIndexes(IndexSet(integer: prevRow), byExtendingSelection: false)
                resultsTableView.scrollRowToVisible(prevRow)
            }
            return true
        } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Handle Enter key
            let row = resultsTableView.selectedRow
            if row >= 0 && row < searchResults.count {
                onSelect?(searchResults[row])
                toggleSearch()
            }
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Handle Escape key
            toggleSearch()
            return true
        }
        
        return false
    }
    
    public func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field == searchField else { return }
        filterResults(query: field.stringValue)
    }
    
    private func filterResults(query: String) {
        guard let stack = stack else { return }
        if query.isEmpty {
            searchResults = []
        } else {
            let lowerQuery = query.localizedLowercase
            let allItems = stack.firstItems(n: stack.count)
            
            searchResults = allItems.filter { item in
                return isFuzzyMatch(query: lowerQuery, text: item.fullText.localizedLowercase)
            }
        }
        resultsTableView.reloadData()
    }
    
    private func isFuzzyMatch(query: String, text: String) -> Bool {
        if query.isEmpty { return true }
        var queryIndex = query.startIndex
        var textIndex = text.startIndex
        
        while queryIndex < query.endIndex && textIndex < text.endIndex {
            if query[queryIndex] == text[textIndex] {
                queryIndex = query.index(after: queryIndex)
            }
            textIndex = text.index(after: textIndex)
        }
        
        return queryIndex == query.endIndex
    }
    
    // NSTableViewDataSource
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return searchResults.count
    }
    
    // NSTableViewDelegate
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = searchResults[row]
        let cell = NSTextField()
        cell.isEditable = false
        cell.isBordered = false
        cell.backgroundColor = .clear
        
        // Highlight logic
        let attrStr = NSMutableAttributedString(string: item.shortenedText)
        attrStr.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: attrStr.length))
        attrStr.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: attrStr.length))
        
        let query = searchField.stringValue.localizedLowercase
        let text = item.shortenedText.localizedLowercase
        
        if !query.isEmpty {
            var queryIndex = query.startIndex
            var textIndex = text.startIndex
            
            while queryIndex < query.endIndex && textIndex < text.endIndex {
                if query[queryIndex] == text[textIndex] {
                    let range = NSRange(textIndex...textIndex, in: text)
                    attrStr.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: range)
                    attrStr.addAttribute(.foregroundColor, value: NSColor.yellow, range: range)
                    queryIndex = query.index(after: queryIndex)
                }
                textIndex = text.index(after: textIndex)
            }
        }
        
        // Append date
        let dateStr = "  " + dateFormatter.string(from: item.createdAt)
        let dateAttrStr = NSAttributedString(string: dateStr, attributes: [
            .foregroundColor: NSColor.lightGray,
            .font: NSFont.systemFont(ofSize: 12)
        ])
        attrStr.append(dateAttrStr)
        
        cell.attributedStringValue = attrStr
        return cell
    }
    
    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = resultsTableView.selectedRow
        guard row >= 0 && row < searchResults.count else {
            previewTextView.string = ""
            return
        }
        let item = searchResults[row]
        previewTextView.string = item.fullText
        setTimestamp(item.createdAt)
    }
    
    public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return true
    }

    public func shouldSelectionPaste() -> Bool {
        // Unlike the menu manager version, there's no toggling.
        let paste =
 UserDefaults.standard.value(forKey: SettingsPath.bezelSelectionPastes.rawValue) as? Bool ?? false
        return paste
    }

    public func setKeyDownHandler(handler: @escaping (NSEvent) -> Void) {
        window.keyDownHandler = handler
    }

    public func setMetaKeyReleaseHandler(handler: @escaping () -> Void) {
        window.metaKeyReleaseHandler = handler
    }

    public func setText(text: String) {
        mainOutlet.setText(text: text)
    }
    
    public func setTimestamp(_ date: Date) {
        timestampLabel.stringValue = dateFormatter.string(from: date)
    }

    public func setSecondaryText(text: String) {
        secondaryOutlet?.setText(text: text, align: .center)
    }

    public func setWindowSize(size: CGSize) {
        var newFrame = window.frame
        newFrame.size.height = size.height
        newFrame.size.width = size.width
        window.setFrame(newFrame, display: true)
    }

    func buildWindow(
        windowAlpha: Double,
        windowBackgroundColor: NSColor,
        windowCornerRadius: Double
    ) {
        // Not under caller's control
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = true
        window.isOpaque = false
        window.level = .modalPanel
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        window.alphaValue = CGFloat(windowAlpha)

        let contentView = NSView(frame: self.window.frame)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer!.cornerRadius = CGFloat(windowCornerRadius)
        contentView.layer!.masksToBounds = true
        contentView.layer!.backgroundColor = windowBackgroundColor.cgColor

        //        let effectView = NSVisualEffectView(frame: self.window.frame)
        //        effectView.translatesAutoresizingMaskIntoConstraints = false
        //        // Could also be ".popover" for a lighter appearance
        //        effectView.material = .dark
        //        effectView.state = .active
        //        effectView.translatesAutoresizingMaskIntoConstraints = false
        //
        //        contentView.addSubview(effectView)
        self.window.collectionBehavior.insert(.fullScreenAuxiliary)
        self.window.collectionBehavior.insert(.ignoresCycle)
        self.window.collectionBehavior.insert(.moveToActiveSpace)
        self.window.contentView = contentView
    }

    public func hide() {
        window.orderOut(nil)
        shown = false
    }

    public func show() {
        // Position the bezel on the screen currently accepting
        // keyboard input, not "the first screen where it appeared";
        // if we don't do this every time, changing the display
        // setup leads to bad behavior.
        //
        // Relatedly there's strange behavior the first time we display, if
        // we're trying to display to a secondary screen, where it just...
        // doesn't appear. (And AFAICT continues to not appear until you switch
        // mainScreen to screen 0.) So we'll accept a mild inconvenience (a check
        // against a boolean, and a possible flash of the bezel) to deal with this.
        // For tracking down purposes of the bug, it seems to be caused by the
        // center call occuring before the window has been shown makeKeyAndOrderFront;
        // commenting out window.center() solves the issue while obviously introducing
        // its own problems.
        if let mainScreen = NSScreen.main {
            if !hasBeenOpened && mainScreen != NSScreen.screens[0] {
                window.makeKeyAndOrderFront(self)
            }
            window.setFrameOrigin(mainScreen.visibleFrame.origin)
        }
        window.center()
        window.makeKeyAndOrderFront(self)
        shown = true
        hasBeenOpened = true
    }

}

private struct OutletFontConfig {
    let color: NSColor
    let size: Int
    let monospaced: Bool
}

class EscapeView: NSView {
    // ^-ESC doesn't naturally trigger a keyDown event; it's bound
    // to cancelOperation by the default NSResponder. We may need
    // to do something similar someday to avoid the Command-. binding.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        // escape
        case 53:
            super.keyDown(with: event)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

private class Outlet {

    let embedderView: NSView
    let textView: NSTextView
    var fontConfig: OutletFontConfig

    public init(
        width: CGFloat,
        height: CGFloat,
        backgroundColor: NSColor,
        cornerRadius: Double,
        borderWidth: Double,
        borderColor: NSColor,
        fontSize: Int = 14,
        fontColor: NSColor = .white
    ) {
        let embedderRect = NSRect(x: 0, y: 0, width: width, height: height)
        embedderView = EscapeView(frame: embedderRect)

        textView = NSTextView(
            frame: NSRect(
                x: 2, y: 1, width: embedderRect.size.width - 4, height: embedderRect.size.height - 2
            )
        )
        textView.isEditable = false
        textView.isSelectable = false
        // This is critical to preventing partial lines from displaying
        textView.textContainer!.lineBreakMode = .byClipping
        textView.backgroundColor = backgroundColor
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.textContainerInset = NSSize(width: 1, height: 1)

        embedderView.translatesAutoresizingMaskIntoConstraints = false
        embedderView.wantsLayer = true

        embedderView.layer?.borderColor = borderColor.cgColor
        embedderView.layer?.borderWidth = CGFloat(borderWidth)
        embedderView.layer?.cornerRadius = CGFloat(cornerRadius)
        embedderView.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.widthAnchor.constraint(equalTo: embedderView.widthAnchor, constant: -2),
            textView.heightAnchor.constraint(equalTo: embedderView.heightAnchor, constant: -2),
            textView.centerXAnchor.constraint(equalTo: embedderView.centerXAnchor),
            textView.centerYAnchor.constraint(equalTo: embedderView.centerYAnchor)
        ])

        fontConfig = OutletFontConfig(
            color: fontColor,
            size: fontSize,
            monospaced: false
        )
    }

    public func setText(text: String) {
        self.setText(text: text, align: nil)
    }

    public func setText(text: String, align: BezelAlignment?) {
        // swiftlint:disable:next line_length
        // Monospacing: https://stackoverflow.com/questions/46642335/how-do-i-get-a-monospace-font-that-respects-acessibility-settings
        let paragraph = NSMutableParagraphStyle()
        var useAlign = align
        paragraph.lineSpacing = 1.2
        if useAlign == nil {
            let pref = UserDefaults.standard.object(forKey: SettingsPath.bezelAlignment.rawValue) as? String
            useAlign = BezelAlignment(rawValue: pref ?? BezelAlignment.center.rawValue) ?? BezelAlignment.center
        }
        switch useAlign {
        case .smartAlign:
            if text.count > 100 || text.contains(where: { $0.isNewline }) {
                paragraph.alignment = .left
            } else {
                paragraph.alignment = .center
            }
        case .left:
            paragraph.alignment = .left
        case .right:
            paragraph.alignment = .right
        default:
            paragraph.alignment = .center
        }
        // We could set it to center here.
        let font: NSFont
        if fontConfig.monospaced {
            // NB: We only have access to SF Mono/monospacedSystemFont in 10.15 or later.
            if #available(OSX 10.15, *) {
                // SF Mono looks significantly better than Courier New.
                font = NSFont.monospacedSystemFont(ofSize: CGFloat(fontConfig.size), weight: NSFont.Weight.medium)
            } else {
                font = NSFont(name: "Courier New", size: CGFloat(fontConfig.size))!
            }
        } else {
            font = NSFont.systemFont(ofSize: CGFloat(fontConfig.size))
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fontConfig.color,
            .paragraphStyle: paragraph
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        textView.textStorage?.setAttributedString(attrString)
    }
}

class KeyCaptureWindow: NSWindow {

    override var acceptsFirstResponder: Bool { return true }
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }

    fileprivate var metaKeyReleaseHandler: (() -> Void)?
    fileprivate var keyDownHandler: ((NSEvent) -> Void)?

    override func keyDown(with event: NSEvent) {
        // We will not pass through keyDown events while the bezel is active.
        // super.keyDown(with: event)
        if let keyDown = keyDownHandler {
            keyDown(event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        return
    }

    override func flagsChanged(with event: NSEvent) {
        if !event.modifierFlags.contains(.option) &&
                !event.modifierFlags.contains(.command) &&
                !event.modifierFlags.contains(.control) &&
                !event.modifierFlags.contains(.shift) {
            if let keyRelease = metaKeyReleaseHandler {
                keyRelease()
            }
        }
        super.flagsChanged(with: event)
    }
}
