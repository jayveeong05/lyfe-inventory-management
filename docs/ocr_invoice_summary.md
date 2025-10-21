# Invoice OCR Analysis Summary

## Invoice Sample Findings
- Directory inspected: 
- PDF batch contains dozens of production invoices (, , ..., ).
- Spot checks show text operators () with embedded Type42 fonts → invoices are digitally generated with selectable text.
- Files such as  include vector text layered over images but still expose textual data; no fully raster-only scans observed in the sample set.

## Recommended Extraction Strategy
1. **Primary Path – PDF Text Parsing**
   - Use a lightweight Flutter-friendly parser (, , or similar).
   - Extract text on upload, normalize whitespace, and run targeted regex/heuristics to derive invoice number and date.
   - Autofill the UI fields with parsed values while keeping them editable so users can correct mismatches.
   - Log surrounding text when matches fail to refine patterns over time.

2. **Fallback for Image-Only PDFs (if encountered later)**
   - **On-device**: Google ML Kit Text Recognition (). Adds ~20–30 MB but keeps processing local.
   - **Server-side**: Cloud OCR (Google Vision / AWS Textract) via Cloud Functions. Keeps the client slim but requires billing-enabled backend and async UI handling.

## Rationale
- Direct text extraction covers the currently available invoices without inflating the app bundle, avoiding the emulator storage issue seen with heavier OCR libraries.
- Hybrid design leaves room for high-confidence automation while respecting manual overrides when OCR/parsing confidence is low.

## Suggested Next Steps
1. Prototype the PDF text parser against a representative subset of invoices and validate regex accuracy for invoice number/date.
2. Instrument parsing logs for quick iteration on edge cases.
3. Decide on fallback OCR approach only if real-world usage reveals image-only documents.
