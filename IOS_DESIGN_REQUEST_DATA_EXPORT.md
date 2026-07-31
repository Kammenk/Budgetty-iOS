# Budgetty iOS — Data export: CSV & PDF

**Design brief for Claude design.** Produce the visual mockups for **CSV & PDF
export**: a human-readable spreadsheet (CSV) and a branded statement (PDF) for
taxes / expenses / sharing, complementing the existing JSON backup. **Android gets
the identical feature** (Android repo's `DATA_EXPORT_DESIGN_REQUEST.md`); this brief
renders it in the iOS **Liquid Glass** language for a native SwiftUI build. Keep parity.

Deliver **light + dark**, **iPhone**, plus **iPad** where noted. Mockups as
HTML/CSS in the Budgetty iOS design project — match the **Account / Settings**
screen most closely, since export lives there beside Backup.

---

## What this is
- **CSV** → open in Numbers/Excel/Sheets; **PDF** → a clean, branded spending
  **statement**. Distinct from JSON backup (opaque, migration-only) — export is for humans.
- **Premium feature.** Free users tapping **Export** hit the paywall.

## Where it lives
On the **Account / Settings** screen, next to the existing **Backup / Restore** — a
new **Export** row opening an **export options sheet**, then handing the file to the
iOS share sheet (`ShareLink` / share sheet).

## Screens / states to draw
1. **Account — Export row:** the new row (Premium), and its **Premium-locked** variant ("Unlock export").
2. **Export options sheet:**
   - **Format** — **CSV (spreadsheet)** / **PDF (statement)** segmented toggle.
   - **Period** — This month / Last month / Last 3 / Last 6 / All time **+ Custom range**.
   - **Categories** — *All categories* (optional narrow).
   - Primary **Export** glass pill.
3. **The PDF statement layout** — *the key visual*. A branded one-page statement:
   header (Budgetty wordmark, period, total spent / income / net), a **by-category
   summary table** (emoji + name + total + %), and a **transactions table** (date ·
   store · category · amount). Make it attach-to-an-email clean.
4. **Success / share:** file ready → the iOS share sheet (a representative "Export ready" moment).
5. **Empty period:** *"Nothing to export for this period."*

## Copy reference
- **Export**, **Export your data**
- **CSV (spreadsheet)**, **PDF (statement)**
- **Period**, **Custom range**, **All categories**, **Export**
- Paywall: **Unlock export**
- Empty: *"Nothing to export for this period."*

## States to make sure the mockups cover
- Export row **locked** (free) and **unlocked** (Premium).
- Options sheet with the CSV/PDF toggle + period + category filter.
- The **branded PDF statement** page (portrait, print-friendly).
- Success/share state and the empty-period state.
- **Light and dark**, **iPhone**, and an **iPad** rendering of the options sheet + the statement.

## Constraints / keep intact
- **Liquid Glass restraint** — glass on the Export CTA / paywall; the options sheet rows are quiet content.
- The **PDF is a document** — it can lean lighter / print-friendly, but keep the brand accent + category colors.
- **16-language tolerance**; never design to English width.
- **Native, no libraries** — CSV string building; **PDF via PDFKit / UIGraphicsPDFRenderer**; share via the system sheet.

---

*Source of truth for content & behavior: the Android repo's
`DATA_EXPORT_DESIGN_REQUEST.md`. iOS build = native CSV + PDFKit over the existing
transactions/income filtered by the chosen period/category; the Export row + action
gate on the same `isPremium` check.*
