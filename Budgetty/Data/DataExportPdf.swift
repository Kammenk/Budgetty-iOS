//
//  DataExportPdf.swift
//  Budgetty
//
//  The branded PDF statement (Android's DataExporter.renderPdf, ported to UIGraphicsPDFRenderer).
//  A4 pages: header + three tiles (spent / income / net), a by-category summary with bars, and the
//  transaction table paginated across pages. Native drawing, no libraries.
//

import UIKit

enum DataExporter {

    private static let pageW: CGFloat = 595   // A4 @ 72dpi
    private static let pageH: CGFloat = 842
    private static let margin: CGFloat = 40

    private static let primary = UIColor(argb: 0xFF6650A4)
    private static let good = UIColor(argb: 0xFF2E7D32)
    private static let ink = UIColor(argb: 0xFF1D1B20)
    private static let muted = UIColor(argb: 0xFF6E6878)
    private static let tileBg = UIColor(argb: 0xFFF7F2FA)
    private static let line = UIColor(argb: 0xFFE3DDEA)
    private static let zebra = UIColor(argb: 0xFFFAF8FC)
    private static let rowInk = UIColor(argb: 0xFF49454F)

    static func renderPdf(_ data: ExportData) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        let pages = paginate(data.rows, first: 16, later: 46)
        return renderer.pdfData { ctx in
            for (i, pageRows) in pages.enumerated() {
                ctx.beginPage()
                drawPage(ctx.cgContext, data: data, pageRows: pageRows,
                         firstPage: i == 0, pageNo: i + 1, pageCount: pages.count)
            }
        }
    }

    private static func paginate(_ rows: [ExportRow], first: Int, later: Int) -> [[ExportRow]] {
        if rows.isEmpty { return [[]] }
        var out: [[ExportRow]] = [Array(rows.prefix(first))]
        var i = min(first, rows.count)
        while i < rows.count { out.append(Array(rows[i..<min(i + later, rows.count)])); i += later }
        return out
    }

    private static func drawPage(_ cg: CGContext, data: ExportData, pageRows: [ExportRow],
                                 firstPage: Bool, pageNo: Int, pageCount: Int) {
        var y = margin
        let right = pageW - margin

        if firstPage {
            text("Budgetty", x: margin, baselineY: y + 16, size: 19, bold: true, color: ink)
            text("Spending statement", x: margin, baselineY: y + 29, size: 9, color: muted)
            text(data.periodLabel, baselineY: y + 14, size: 15, bold: true, color: ink, rightEdge: right)
            text(data.generatedLabel, baselineY: y + 27, size: 9, color: muted, rightEdge: right)
            y += 44
            fill(cg, CGRect(x: margin, y: y, width: pageW - 2 * margin, height: 3), primary)
            y += 18

            // Three tiles
            let tileW = (pageW - 2 * margin - 24) / 3
            let tiles: [(String, String, UIColor)] = [
                ("TOTAL SPENT", money(data.totalSpent, data.currencySymbol), ink),
                ("INCOME", money(data.income, data.currencySymbol), ink),
                ("NET", (data.net >= 0 ? "+" : "") + money(data.net, data.currencySymbol), data.net >= 0 ? good : ink),
            ]
            for (i, tile) in tiles.enumerated() {
                let x = margin + CGFloat(i) * (tileW + 12)
                roundRect(cg, CGRect(x: x, y: y, width: tileW, height: 56), radius: 10, tileBg)
                text(tile.0, x: x + 13, baselineY: y + 20, size: 8, bold: true, color: muted)
                text(tile.1, x: x + 13, baselineY: y + 44, size: 20, bold: true, color: tile.2)
            }
            y += 56 + 24

            sectionHeader(cg, "BY CATEGORY", y: y); y += 20
            for cat in data.byCategory {
                circle(cg, cx: margin + 5, cy: y + 4, r: 4.5, UIColor(argb: cat.colorArgb))
                text(cat.emoji, x: margin + 16, baselineY: y + 8, size: 11, color: ink)
                text(cat.name, x: margin + 34, baselineY: y + 8, size: 11, bold: true, color: ink)
                let barX = margin + 150, barW = pageW - margin - 150 - 110
                roundRect(cg, CGRect(x: barX, y: y + 1, width: barW, height: 6), radius: 3, UIColor(argb: 0xFFF1ECF6))
                let frac = CGFloat(min(max(cat.pct, 0), 100)) / 100
                roundRect(cg, CGRect(x: barX, y: y + 1, width: barW * frac, height: 6), radius: 3, UIColor(argb: cat.colorArgb))
                text("\(cat.pct)%", baselineY: y + 8, size: 10, color: muted, rightEdge: pageW - margin - 72)
                text(money(cat.total, data.currencySymbol), baselineY: y + 8, size: 11, bold: true, color: ink, rightEdge: right)
                y += 17
                fill(cg, CGRect(x: margin, y: y, width: pageW - 2 * margin, height: 0.5), UIColor(argb: 0xFFEFEAF4))
                y += 5
            }
            y += 18
            sectionHeader(cg, "TRANSACTIONS", y: y)
            text("\(data.rows.count) in this period", baselineY: y + 4, size: 9, color: muted, rightEdge: right)
            y += 20
        } else {
            text("TRANSACTIONS (cont.)", x: margin, baselineY: y + 10, size: 11, bold: true, color: ink)
            y += 24
        }

        // Table header
        text("DATE", x: margin + 8, baselineY: y, size: 8, bold: true, color: muted)
        text("STORE", x: margin + 70, baselineY: y, size: 8, bold: true, color: muted)
        text("CATEGORY", x: pageW - margin - 180, baselineY: y, size: 8, bold: true, color: muted)
        text("AMOUNT", baselineY: y, size: 8, bold: true, color: muted, rightEdge: pageW - margin - 8)
        y += 6

        for (i, r) in pageRows.enumerated() {
            if i % 2 == 1 { roundRect(cg, CGRect(x: margin, y: y - 2, width: pageW - 2 * margin, height: 14), radius: 4, zebra) }
            text(r.dateLabel, x: margin + 8, baselineY: y + 9, size: 10, color: rowInk)
            text(ellipsize(r.store, maxW: pageW - margin - 180 - (margin + 70) - 6, size: 11, bold: true),
                 x: margin + 70, baselineY: y + 9, size: 11, bold: true, color: ink)
            circle(cg, cx: pageW - margin - 180 + 3, cy: y + 5, r: 3.5, UIColor(argb: r.colorArgb))
            text(ellipsize(r.category, maxW: 80, size: 10), x: pageW - margin - 180 + 12, baselineY: y + 9, size: 10, color: rowInk)
            text(money(r.amount, data.currencySymbol), baselineY: y + 9, size: 11, bold: true, color: ink, rightEdge: pageW - margin - 8)
            y += 15
        }

        if pageNo == pageCount {
            fill(cg, CGRect(x: margin, y: y + 4, width: pageW - 2 * margin, height: 2), primary)
            y += 16
            text(data.totalRowLabel, x: margin + 8, baselineY: y + 8, size: 12, bold: true, color: ink)
            text(money(data.totalSpent, data.currencySymbol), baselineY: y + 8, size: 13, bold: true, color: ink, rightEdge: pageW - margin - 8)
        }

        fill(cg, CGRect(x: margin, y: pageH - margin - 22, width: pageW - 2 * margin, height: 0.5), line)
        text("Created on device by Budgetty from your own receipts. Not a tax document or a bank statement.",
             x: margin, baselineY: pageH - margin - 8, size: 8, color: UIColor(argb: 0xFF8A8496))
        text("Page \(pageNo) of \(pageCount)", baselineY: pageH - margin - 8, size: 8, color: UIColor(argb: 0xFF8A8496), rightEdge: right)
    }

    // MARK: - Drawing helpers

    private static func text(_ s: String, x: CGFloat = 0, baselineY: CGFloat, size: CGFloat,
                             bold: Bool = false, color: UIColor, rightEdge: CGFloat? = nil) {
        let font = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let ns = s as NSString
        let topY = baselineY - font.ascender
        if let rightEdge { ns.draw(at: CGPoint(x: rightEdge - ns.size(withAttributes: attrs).width, y: topY), withAttributes: attrs) }
        else { ns.draw(at: CGPoint(x: x, y: topY), withAttributes: attrs) }
    }
    private static func sectionHeader(_ cg: CGContext, _ s: String, y: CGFloat) {
        text(s, x: margin, baselineY: y + 4, size: 11, bold: true, color: ink)
        let w = (s as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .bold)]).width
        fill(cg, CGRect(x: margin + w + 10, y: y + 1, width: pageW - margin - (margin + w + 10), height: 1), line)
    }
    private static func fill(_ cg: CGContext, _ rect: CGRect, _ color: UIColor) {
        cg.setFillColor(color.cgColor); cg.fill(rect)
    }
    private static func roundRect(_ cg: CGContext, _ rect: CGRect, radius: CGFloat, _ color: UIColor) {
        cg.setFillColor(color.cgColor)
        UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
    }
    private static func circle(_ cg: CGContext, cx: CGFloat, cy: CGFloat, r: CGFloat, _ color: UIColor) {
        cg.setFillColor(color.cgColor)
        cg.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }
    private static func ellipsize(_ s: String, maxW: CGFloat, size: CGFloat, bold: Bool = false) -> String {
        let font = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        if (s as NSString).size(withAttributes: attrs).width <= maxW { return s }
        var t = s
        while !t.isEmpty && ((t + "…") as NSString).size(withAttributes: attrs).width > maxW { t.removeLast() }
        return t + "…"
    }
    private static func money(_ v: Decimal, _ symbol: String) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
        return "\(f.string(from: v as NSDecimalNumber) ?? "\(v)") \(symbol)"
    }
}

extension UIColor {
    convenience init(argb: Int) {
        self.init(red: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
                  blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat((argb >> 24) & 0xFF) / 255)
    }
}
