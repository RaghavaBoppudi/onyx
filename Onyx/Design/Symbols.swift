//  Symbols.swift
//  Every SF Symbol name in the app. Stock symbols only — no custom glyphs, so the
//  chrome matches what the system camera and every other iOS app already use.
//
//  Toggle-style icons (grid, settings, flash) carry an outline/filled pair rather
//  than a single name. iOS convention for an on/off control is to swap glyph shape,
//  not just tint — a filled gear reads as "engaged" even at a glance, before colour
//  registers. `ChromeIcon` picks between the two based on `isActive`.

struct SymbolPair {
    let outline: String
    let filled: String
}

enum Symbols {
    static let grid = SymbolPair(outline: "square.grid.3x3", filled: "square.grid.3x3.fill")
    static let settings = SymbolPair(outline: "gearshape", filled: "gearshape.fill")

    static let flashOff  = SymbolPair(outline: "bolt.slash", filled: "bolt.slash.fill")
    static let flashOn   = SymbolPair(outline: "bolt", filled: "bolt.fill")

    static let noPermission = "camera.metering.unknown"
}
