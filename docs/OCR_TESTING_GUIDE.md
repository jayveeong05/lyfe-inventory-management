# OCR Invoice Feature - Testing Guide

## Quick Test Steps

### 1. Prerequisites
- Flutter app running on device/emulator
- Sample PDF invoices for testing
- Access to Invoice screen in the app

### 2. Basic Test Flow
1. **Navigate to Invoice Screen**
   - Go to Invoice management
   - Select a Purchase Order with "Pending" status

2. **Upload PDF Invoice**
   - Click "Select PDF File"
   - Choose a PDF invoice from your device
   - Verify file name appears

3. **Test OCR Extraction**
   - Click "Extract Invoice Data" button (appears after file selection)
   - Wait for processing (2-5 seconds)
   - Check if invoice number and date fields are populated

4. **Verify Results**
   - Review extracted invoice number
   - Check extracted date
   - Confirm confidence level in success message

### 3. Test Scenarios

#### Scenario A: High-Quality Invoice
- **Expected**: Auto-fill fields, green success message
- **Test with**: Clear, typed invoices with standard formats

#### Scenario B: Poor-Quality Scan
- **Expected**: Low confidence dialog or manual entry
- **Test with**: Blurry scans, handwritten invoices

#### Scenario C: Complex Layout
- **Expected**: Medium confidence, orange warning
- **Test with**: Multi-column invoices, tables

#### Scenario D: No Recognizable Data
- **Expected**: Error message, manual entry required
- **Test with**: Image-only PDFs, non-invoice documents

### 4. Sample Invoice Formats to Test

Create test PDFs with these formats:

```
Format 1 - Standard Business Invoice:
Invoice Number: INV-2024-001
Invoice Date: 25/12/2024

Format 2 - Simple Format:
Inv #: ABC123
Date: 12-25-2024

Format 3 - Alternative Layout:
Bill No: 2024001
Bill Date: 2024/12/25

Format 4 - Minimal Format:
XYZ456
25/12/2024
```

### 5. Expected Behaviors

#### Success Cases
- ✅ Fields auto-populate with correct data
- ✅ Green/orange success message appears
- ✅ User can edit extracted data
- ✅ Form validation works normally

#### Error Cases
- ✅ Clear error messages for failures
- ✅ Graceful fallback to manual entry
- ✅ No app crashes or freezes
- ✅ Loading states work properly

### 6. Performance Checks
- Processing time under 10 seconds
- No memory leaks during repeated use
- Smooth UI during extraction
- Proper cleanup of temporary files

### 7. Debug Information

Check Flutter console for these debug messages:
```
🔍 Starting OCR extraction for: /path/to/file.pdf
📄 Converting PDF to image...
✅ PDF converted to image successfully
📄 Extracted text length: 1234 characters
🔍 Parsing invoice data from text...
📋 Found invoice number: INV-2024-001
📅 Found invoice date: 2024-12-25
🎯 OCR Results - Invoice: INV-2024-001, Date: 2024-12-25, Confidence: 0.9
```

### 8. Common Issues and Solutions

#### Issue: "Extract Invoice Data" button not appearing
- **Solution**: Ensure PDF file is selected first

#### Issue: OCR extraction fails immediately
- **Solution**: Check PDF file is valid and not corrupted

#### Issue: No data extracted from clear invoice
- **Solution**: Check if invoice follows supported formats

#### Issue: Wrong date format extracted
- **Solution**: Verify date parsing logic handles your format

### 9. Manual Testing Checklist

- [ ] PDF file selection works
- [ ] OCR button appears after file selection
- [ ] Loading state shows during processing
- [ ] Success message shows confidence level
- [ ] Invoice number field populates correctly
- [ ] Date field populates correctly
- [ ] Low confidence dialog works
- [ ] Manual override option works
- [ ] Error handling works gracefully
- [ ] Form submission works after OCR
- [ ] Multiple extractions work without issues
- [ ] App performance remains smooth

### 10. Automated Testing Ideas

For future implementation:
```dart
// Unit tests for OCR service
testWidgets('OCR extracts invoice number correctly', (tester) async {
  final ocrService = InvoiceOcrService();
  final testPdf = File('test_assets/sample_invoice.pdf');
  
  final result = await ocrService.extractInvoiceData(testPdf);
  
  expect(result['success'], true);
  expect(result['invoiceNumber'], 'INV-2024-001');
});

// Widget tests for UI integration
testWidgets('OCR button appears after file selection', (tester) async {
  await tester.pumpWidget(MyApp());
  
  // Navigate to invoice screen
  // Select file
  // Verify OCR button appears
});
```

### 11. Performance Benchmarks

Target performance metrics:
- **PDF Conversion**: < 2 seconds
- **Text Recognition**: < 3 seconds
- **Data Parsing**: < 1 second
- **Total Process**: < 6 seconds
- **Memory Usage**: < 50MB additional

### 12. User Acceptance Criteria

The OCR feature is ready when:
- ✅ 80%+ accuracy on standard invoices
- ✅ Graceful handling of all error cases
- ✅ Clear user feedback at all stages
- ✅ No impact on existing functionality
- ✅ Intuitive user experience
- ✅ Proper validation and confirmation flows
