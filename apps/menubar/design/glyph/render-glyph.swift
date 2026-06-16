#!/usr/bin/env swift
// Regenerate the Claude logomark shown in the menu bar.
//   swift design/glyph/render-glyph.swift
// Draws the OFFICIAL Claude symbol (the radial "spark"/sunburst) into a vector
// PDF at apps/menubar/Resources/ClaudeGlyph.pdf. The artwork is the single-path
// Claude AI symbol published on Wikimedia Commons (CC0 / public domain,
// https://commons.wikimedia.org/wiki/File:Claude_AI_symbol.svg). It's filled
// solid black and loaded as a TEMPLATE image (alpha channel only), so the menu
// bar tints it black/white to match the bar.
//
// The mark is defined in SVG units (viewBox 0 0 100 100, y-down). We parse that
// path, recenter it on a square canvas with a small margin, and flip Y so it
// renders upright in CoreGraphics' y-up PDF space. To restyle, replace `pathD`
// with another single-path SVG `d` string and re-run.
import CoreGraphics
import Foundation

// Official Claude symbol path (y-down SVG space, viewBox 0 0 100 100).
let pathD = "m19.6 66.5 19.7-11 .3-1-.3-.5h-1l-3.3-.2-11.2-.3L14 53l-9.5-.5-2.4-.5L0 49l.2-1.5 2-1.3 2.9.2 6.3.5 9.5.6 6.9.4L38 49.1h1.6l.2-.7-.5-.4-.4-.4L29 41l-10.6-7-5.6-4.1-3-2-1.5-2-.6-4.2 2.7-3 3.7.3.9.2 3.7 2.9 8 6.1L37 36l1.5 1.2.6-.4.1-.3-.7-1.1L33 25l-6-10.4-2.7-4.3-.7-2.6c-.3-1-.4-2-.4-3l3-4.2L28 0l4.2.6L33.8 2l2.6 6 4.1 9.3L47 29.9l2 3.8 1 3.4.3 1h.7v-.5l.5-7.2 1-8.7 1-11.2.3-3.2 1.6-3.8 3-2L61 2.6l2 2.9-.3 1.8-1.1 7.7L59 27.1l-1.5 8.2h.9l1-1.1 4.1-5.4 6.9-8.6 3-3.5L77 13l2.3-1.8h4.3l3.1 4.7-1.4 4.9-4.4 5.6-3.7 4.7-5.3 7.1-3.2 5.7.3.4h.7l12-2.6 6.4-1.1 7.6-1.3 3.5 1.6.4 1.6-1.4 3.4-8.2 2-9.6 2-14.3 3.3-.2.1.2.3 6.4.6 2.8.2h6.8l12.6 1 3.3 2 1.9 2.7-.3 2-5.1 2.6-6.8-1.6-16-3.8-5.4-1.3h-.8v.4l4.6 4.5 8.3 7.5L89 80.1l.5 2.4-1.3 2-1.4-.2-9.2-7-3.6-3-8-6.8h-.5v.7l1.8 2.7 9.8 14.7.5 4.5-.7 1.4-2.6 1-2.7-.6-5.8-8-6-9-4.7-8.2-.5.4-2.9 30.2-1.3 1.5-3 1.2-2.5-2-1.4-3 1.4-6.2 1.6-8 1.3-6.4 1.2-7.9.7-2.6v-.2H49L43 72l-9 12.3-7.2 7.6-1.7.7-3-1.5.3-2.8L24 86l10-12.8 6-7.9 4-4.6-.1-.5h-.3L17.2 77.4l-4.7.6-2-2 .2-3 1-1 8-5.5Z"

// --- minimal SVG-path parser: M/m L/l H/h V/v C/c Z/z (the commands this path uses) ---
final class PathScanner {
    let chars: [Character]; var i = 0
    init(_ s: String) { chars = Array(s) }
    var atEnd: Bool { i >= chars.count }
    func skipSep() { while i < chars.count, " ,\n\t".contains(chars[i]) { i += 1 } }
    func peekCmd() -> Character? { skipSep(); guard i < chars.count, chars[i].isLetter else { return nil }; return chars[i] }
    func readCmd() -> Character { let c = chars[i]; i += 1; return c }
    func readNum() -> CGFloat {
        skipSep()
        var s = ""; var seenDot = false; var seenDigit = false
        if i < chars.count, chars[i] == "+" || chars[i] == "-" { s.append(chars[i]); i += 1 }
        while i < chars.count {
            let c = chars[i]
            if c.isNumber { s.append(c); i += 1; seenDigit = true }
            else if c == "." { if seenDot { break }; seenDot = true; s.append(c); i += 1 } // 2nd dot starts a new number
            else if (c == "e" || c == "E") && seenDigit { s.append(c); i += 1; if i < chars.count, chars[i] == "+" || chars[i] == "-" { s.append(chars[i]); i += 1 }; seenDot = true }
            else { break } // includes '-' that begins the next number
        }
        return CGFloat(Double(s) ?? 0)
    }
    func hasNum() -> Bool { skipSep(); guard i < chars.count else { return false }; let c = chars[i]; return c.isNumber || c == "." || c == "-" || c == "+" }
}

func buildPath(_ d: String) -> CGPath {
    let p = CGMutablePath(); let sc = PathScanner(d)
    var cur = CGPoint.zero, start = CGPoint.zero, cmd: Character = " "
    while !sc.atEnd {
        if sc.peekCmd() != nil { cmd = sc.readCmd() }
        switch cmd {
        case "M", "m":
            let rel = (cmd == "m")
            var x = sc.readNum(), y = sc.readNum()
            if rel { x += cur.x; y += cur.y }
            cur = CGPoint(x: x, y: y); start = cur; p.move(to: cur)
            cmd = rel ? "l" : "L" // extra coordinate pairs after a moveto are implicit linetos
            while sc.hasNum() {
                var lx = sc.readNum(), ly = sc.readNum()
                if cmd == "l" { lx += cur.x; ly += cur.y }
                cur = CGPoint(x: lx, y: ly); p.addLine(to: cur)
            }
        case "L", "l":
            let rel = (cmd == "l")
            while sc.hasNum() { var x = sc.readNum(), y = sc.readNum(); if rel { x += cur.x; y += cur.y }; cur = CGPoint(x: x, y: y); p.addLine(to: cur) }
        case "H", "h":
            let rel = (cmd == "h")
            while sc.hasNum() { var x = sc.readNum(); if rel { x += cur.x }; cur.x = x; p.addLine(to: cur) }
        case "V", "v":
            let rel = (cmd == "v")
            while sc.hasNum() { var y = sc.readNum(); if rel { y += cur.y }; cur.y = y; p.addLine(to: cur) }
        case "C", "c":
            let rel = (cmd == "c")
            while sc.hasNum() {
                var c1 = CGPoint(x: sc.readNum(), y: sc.readNum())
                var c2 = CGPoint(x: sc.readNum(), y: sc.readNum())
                var e  = CGPoint(x: sc.readNum(), y: sc.readNum())
                if rel { c1.x += cur.x; c1.y += cur.y; c2.x += cur.x; c2.y += cur.y; e.x += cur.x; e.y += cur.y }
                p.addCurve(to: e, control1: c1, control2: c2); cur = e
            }
        case "Z", "z":
            p.closeSubpath(); cur = start
        default:
            _ = sc.readNum() // unknown command: consume a number so we can't spin forever
        }
    }
    return p
}

let mark = buildPath(pathD)
let bbox = mark.boundingBoxOfPath

// Square canvas tightly fit to the mark with a small uniform margin, so the
// glyph stays centered and `scaledToFit` controls its size predictably.
let pad: CGFloat = 4
let side = max(bbox.width, bbox.height) + pad * 2

// design/glyph/ → apps/menubar/Resources/ClaudeGlyph.pdf
let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let resources = scriptDir.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let outURL = resources.appendingPathComponent("ClaudeGlyph.pdf")

var media = CGRect(x: 0, y: 0, width: side, height: side)
guard let ctx = CGContext(outURL as CFURL, mediaBox: &media, nil) else {
    fatalError("could not create PDF context at \(outURL.path)")
}
ctx.beginPDFPage(nil)
ctx.setFillColor(CGColor(gray: 0, alpha: 1)) // black; template keeps only the alpha
// Recenter the mark in the square and flip Y (SVG y-down → CoreGraphics y-up).
ctx.translateBy(x: side / 2, y: side / 2)
ctx.scaleBy(x: 1, y: -1)
ctx.translateBy(x: -bbox.midX, y: -bbox.midY)
ctx.addPath(mark)
ctx.fillPath()
ctx.endPDFPage()
ctx.closePDF()
print("wrote \(outURL.path) (\(Int(side))×\(Int(side)) pt)")
