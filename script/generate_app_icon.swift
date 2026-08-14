#!/usr/bin/env swift

// 生成 App 图标（方案 C：笔与墨痕）。
//
// 直接用 CoreGraphics 绘制而不是光栅化一份 SVG：小尺寸需要的不是等比缩小，
// 而是另一张图。16 与 32 像素改用加粗、去掉笔身内部细节的简化图形——把大图
// 缩到 16 像素只会得到一团灰。macOS 的 .icns 本来就允许每档放不同的画法。
//
// 用法：swift script/generate_app_icon.swift <输出目录>
// 产出 AppIcon.iconset/，随后由 iconutil 打包成 .icns。

import AppKit
import CoreGraphics
import Foundation

// 与 WorkshopPalette 同源：琥珀是 App 里「草稿」状态那支色。
let inkAmber = CGColor(srgbRed: 0xD9 / 255, green: 0xA4 / 255, blue: 0x41 / 255, alpha: 1)
let strokeWhite = CGColor(srgbRed: 0xED / 255, green: 0xED / 255, blue: 0xEA / 255, alpha: 1)
let tileTop = CGColor(srgbRed: 0x2A / 255, green: 0x27 / 255, blue: 0x25 / 255, alpha: 1)
let tileBottom = CGColor(srgbRed: 0x13 / 255, green: 0x12 / 255, blue: 0x11 / 255, alpha: 1)
let rimWhite = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)

/// 圆角比例取 macOS 的 squircle 近似值。
let cornerRatio: CGFloat = 0.224

func drawTile(_ ctx: CGContext, size: CGFloat) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let radius = size * cornerRatio
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [tileTop, tileBottom] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
    ctx.restoreGState()

    // 极淡的内描边，让深色图标在深色 Dock 上仍有边界。
    // 只在 64px 以上画：更小的尺寸下 1px 描边压在 3~4px 的圆角上，抗锯齿会在
    // 四角留下亮点，反而比没有边界更脏。
    guard size >= 64 else { return }

    ctx.saveGState()
    let inset = size * 0.006
    let rimRect = rect.insetBy(dx: inset, dy: inset)
    let rimPath = CGPath(
        roundedRect: rimRect,
        cornerWidth: radius - inset,
        cornerHeight: radius - inset,
        transform: nil
    )
    ctx.addPath(rimPath)
    ctx.setStrokeColor(rimWhite)
    ctx.setLineWidth(max(1, size * 0.012))
    ctx.strokePath()
    ctx.restoreGState()
}

/// 归一化坐标（0…100，原点左上）转 CoreGraphics 坐标（原点左下）。
func pt(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat) -> CGPoint {
    CGPoint(x: x / 100 * size, y: (100 - y) / 100 * size)
}

/// 完整画法：笔身轮廓 + 笔环 + 墨痕。用于 512 及以上。
func drawDetailed(_ ctx: CGContext, size: CGFloat) {
    let lineWidth = size * 0.06

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(strokeWhite)
    ctx.setLineWidth(lineWidth)

    let body = CGMutablePath()
    body.move(to: pt(28, 68, size))
    body.addLine(to: pt(37, 47, size))
    body.addLine(to: pt(69, 16, size))
    body.addLine(to: pt(80, 27, size))
    body.addLine(to: pt(48, 58, size))
    body.closeSubpath()
    ctx.addPath(body)
    ctx.strokePath()

    let collar = CGMutablePath()
    collar.move(to: pt(37, 47, size))
    collar.addLine(to: pt(48, 58, size))
    ctx.addPath(collar)
    ctx.strokePath()

    drawInk(ctx, size: size, lineWidth: size * 0.07)
}

/// 简化画法：去掉笔环、加粗、笔身缩短。用于 32 及以下。
func drawSimplified(_ ctx: CGContext, size: CGFloat) {
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(strokeWhite)
    ctx.setLineWidth(size * 0.105)

    // 笔身退化为一条粗对角线：小尺寸下轮廓线之间的空隙会糊死，实心笔画反而更清楚。
    let shaft = CGMutablePath()
    shaft.move(to: pt(32, 64, size))
    shaft.addLine(to: pt(72, 24, size))
    ctx.addPath(shaft)
    ctx.strokePath()

    drawInk(ctx, size: size, lineWidth: size * 0.115)
}

/// 墨痕：一道略带弧度的横线。小尺寸下它退化成一个琥珀色块——
/// 靠颜色而非形状被认出来，这正是选它的理由。
func drawInk(_ ctx: CGContext, size: CGFloat, lineWidth: CGFloat) {
    ctx.setStrokeColor(inkAmber)
    ctx.setLineWidth(lineWidth)

    let ink = CGMutablePath()
    ink.move(to: pt(20, 84, size))
    ink.addCurve(
        to: pt(72, 84, size),
        control1: pt(34, 78, size),
        control2: pt(52, 78, size)
    )
    ctx.addPath(ink)
    ctx.strokePath()
}

func renderPNG(size: Int) throws -> Data {
    let dimension = CGFloat(size)
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw IconError.contextFailed(size)
    }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    drawTile(ctx, size: dimension)

    if size <= 32 {
        drawSimplified(ctx, size: dimension)
    } else {
        drawDetailed(ctx, size: dimension)
    }

    guard let image = ctx.makeImage() else { throw IconError.imageFailed(size) }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw IconError.encodeFailed(size)
    }
    return data
}

enum IconError: LocalizedError {
    case contextFailed(Int)
    case imageFailed(Int)
    case encodeFailed(Int)
    case missingOutputDirectory

    var errorDescription: String? {
        switch self {
        case let .contextFailed(size): "无法为 \(size)px 创建绘图上下文"
        case let .imageFailed(size): "无法生成 \(size)px 位图"
        case let .encodeFailed(size): "无法编码 \(size)px PNG"
        case .missingOutputDirectory: "用法：swift script/generate_app_icon.swift <输出目录>"
        }
    }
}

// iconset 要求的文件名与尺寸对应关系由 iconutil 强制校验，写错会打包失败。
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

do {
    guard CommandLine.arguments.count > 1 else { throw IconError.missingOutputDirectory }
    let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
    let iconset = outputDirectory.appending(path: "AppIcon.iconset")

    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    // 同一像素尺寸只渲染一次，@1x/@2x 共用同一张图。
    var rendered: [Int: Data] = [:]
    for variant in variants {
        let data: Data
        if let cached = rendered[variant.pixels] {
            data = cached
        } else {
            data = try renderPNG(size: variant.pixels)
            rendered[variant.pixels] = data
        }
        try data.write(to: iconset.appending(path: variant.name), options: .atomic)
    }

    print("AppIcon.iconset 已生成：\(rendered.count) 个尺寸，\(variants.count) 个条目")
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
