#!/usr/bin/env swift
// Regenerate the Claude "sunburst" glyph shown in the menu bar.
//   swift design/glyph/render-glyph.swift
// Draws a monochrome (black-on-transparent) radial burst into a vector PDF at
// apps/menubar/Resources/ClaudeGlyph.pdf. It's loaded as a TEMPLATE image
// (alpha channel only), so the menu bar tints it black/white to match the bar.
// Tweak the geometry constants below and re-run to restyle.
import CoreGraphics
import Foundation

// --- geometry (vector pt; scales freely) ---
let canvas: CGFloat = 100
let rayCount = 12
let rInner: CGFloat = 9      // empty gap at the center
let rOuter: CGFloat = 46     // tip radius (canvas/2 = 50 → ~4pt margin)
let halfWidth: CGFloat = 4.6 // petal bulge half-width at the mid radius

let center = CGPoint(x: canvas / 2, y: canvas / 2)
let rMid = (rInner + rOuter) / 2

// design/glyph/ → apps/menubar/Resources/ClaudeGlyph.pdf
let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let resources = scriptDir.deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources")
try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let outURL = resources.appendingPathComponent("ClaudeGlyph.pdf")

var box = CGRect(x: 0, y: 0, width: canvas, height: canvas)
guard let ctx = CGContext(outURL as CFURL, mediaBox: &box, nil) else {
    fatalError("could not create PDF context at \(outURL.path)")
}
ctx.beginPDFPage(nil)
ctx.setFillColor(CGColor(gray: 0, alpha: 1)) // black; template keeps only the alpha

for i in 0..<rayCount {
    let angle = (CGFloat(i) / CGFloat(rayCount)) * 2 * .pi
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle)
    // A pointed petal along +Y: tips at rInner/rOuter, bulging to ±halfWidth.
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 0, y: rInner))
    ctx.addQuadCurve(to: CGPoint(x: 0, y: rOuter), control: CGPoint(x: halfWidth, y: rMid))
    ctx.addQuadCurve(to: CGPoint(x: 0, y: rInner), control: CGPoint(x: -halfWidth, y: rMid))
    ctx.closePath()
    ctx.fillPath()
    ctx.restoreGState()
}

ctx.endPDFPage()
ctx.closePDF()
print("wrote \(outURL.path)")
