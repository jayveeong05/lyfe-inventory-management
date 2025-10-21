# PDF Text Extraction Feature

## Overview

The PDF text extraction feature automatically extracts invoice numbers and dates from uploaded PDF files. This reduces manual data entry and improves accuracy.

**PDF-Only Approach**:
- **PDF Files Only**: Uses Syncfusion Flutter PDF library for direct text extraction (fast and accurate)
- **Cross-Platform**: Works reliably on all platforms (Android, iOS, Windows, macOS, Linux, Web)
- **Simplified**: Single file type support for consistent user experience

## Features

- **Direct PDF Text Extraction**: Uses Syncfusion Flutter PDF library for fast, accurate text extraction from PDF files
- **Cross-Platform Support**: Works on all platforms (Android, iOS, Windows, macOS, Linux, Web)
- **Smart Data Parsing**: Extracts invoice numbers and dates using multiple regex patterns
- **Confidence Scoring**: Provides confidence levels for extracted data
- **User Validation**: Shows confirmation dialog for low-confidence results
- **Manual Override**: Users can always edit or manually enter data
- **Simplified Workflow**: Single file type support reduces complexity

## How It Works

### 1. User Workflow
1. User uploads a PDF file
2. "Extract PDF Data" button appears
3. User clicks the button to start extraction
4. System extracts text directly from PDF
5. Form fields are auto-populated with extracted data
6. User reviews and corrects data if needed

### 2. Technical Process

**For PDF Files:**
1. **Direct Text Extraction**: Syncfusion PDF library extracts text directly from PDF
2. **Data Parsing**: Regex patterns search for invoice numbers and dates
3. **Confidence Calculation**: System calculates confidence based on matches found

**For Image Files:**
1. **OCR Processing**: Google ML Kit processes the image to extract text
2. **Data Parsing**: Regex patterns search for invoice numbers and dates
3. **Confidence Calculation**: System calculates confidence based on matches found

**Final Step:**
4. **User Interaction**: High confidence results auto-fill, low confidence shows dialog

## Supported Invoice Formats

### Invoice Number Patterns
- `Invoice No: ABC123`
- `Invoice Number: 2024-001`
- `Inv #: XYZ-456`
- `Bill No: 789`
- Standalone alphanumeric codes (e.g., `ABC1234`, `2024001`)

### Date Patterns
- `Invoice Date: 25/12/2024`
- `Date: 12-25-2024`
- `Bill Date: 2024/12/25`
- Standalone date formats: `DD/MM/YYYY`, `MM/DD/YYYY`, `YYYY/MM/DD`

## Confidence Levels

- **High Confidence (70-100%)**: Auto-fills fields, shows green success message
- **Medium Confidence (50-69%)**: Auto-fills fields, shows orange warning message
- **Low Confidence (0-49%)**: Shows validation dialog for user confirmation

## Error Handling

### Common Issues and Solutions

1. **PDF Conversion Failed**
   - **Cause**: Corrupted PDF or unsupported format
   - **Solution**: User sees error message, can try different file

2. **No Text Recognized**
   - **Cause**: Image-only PDF or poor quality scan
   - **Solution**: User enters data manually

3. **Low Extraction Confidence**
   - **Cause**: Complex layout or unclear text
   - **Solution**: Validation dialog allows user to review and choose

4. **OCR Service Initialization Failed**
   - **Cause**: Device compatibility or memory issues
   - **Solution**: Graceful fallback to manual entry

## Usage Instructions

### For Users
1. **Upload PDF**: Select your invoice PDF file
2. **Extract Data**: Click "Extract Invoice Data" button
3. **Review Results**: Check the auto-filled invoice number and date
4. **Correct if Needed**: Edit any incorrect data
5. **Submit**: Continue with normal invoice upload process

### For Developers
```dart
// Initialize OCR service
final ocrService = InvoiceOcrService();
await ocrService.initialize();

// Extract data from PDF
final result = await ocrService.extractInvoiceData(pdfFile);

// Check results
if (result['success']) {
  final invoiceNumber = result['invoiceNumber'];
  final invoiceDate = result['invoiceDate'];
  final confidence = result['confidence'];
}
```

## Performance Considerations

- **Processing Time**: 2-5 seconds for typical invoice PDFs
- **Memory Usage**: ~20-30MB additional for ML Kit models
- **Storage**: Temporary image files are automatically cleaned up
- **Network**: No internet required - all processing is on-device

## Privacy and Security

- **On-Device Processing**: All OCR happens locally, no data sent to cloud
- **Temporary Files**: PDF images are stored temporarily and deleted after processing
- **No Data Retention**: Extracted text is not stored permanently

## Troubleshooting

### Common Problems

1. **Button Not Appearing**
   - Ensure PDF file is selected first
   - Check file format is PDF

2. **Extraction Takes Too Long**
   - Large PDF files may take longer
   - Try with smaller/simpler invoices

3. **Poor Extraction Accuracy**
   - Ensure invoice has clear, readable text
   - Try scanning at higher resolution
   - Consider manual entry for complex layouts

### Debug Information

The OCR service provides detailed logging:
- PDF conversion status
- Text extraction length
- Parsing results
- Confidence calculations

Check Flutter console for debug messages starting with:
- `🔍` - OCR process start
- `📄` - PDF conversion
- `📋` - Invoice number found
- `📅` - Date found
- `✅` - Success
- `❌` - Error

## Future Enhancements

Potential improvements for future versions:
- Support for multi-page PDFs
- Additional data extraction (amounts, vendor info)
- Machine learning model training for better accuracy
- Support for more invoice formats
- Batch processing capabilities

## Dependencies

- `google_ml_kit: ^0.18.0` - Text recognition for image files
- `syncfusion_flutter_pdf: ^26.2.14` - Direct PDF text extraction
- `path: ^1.9.0` - File path utilities

## API Reference

### InvoiceOcrService

#### Methods
- `initialize()` - Initialize the OCR service
- `extractInvoiceData(File pdfFile)` - Extract data from PDF
- `dispose()` - Clean up resources
- `isAvailable` - Check if service is ready

#### Return Format
```dart
{
  'success': bool,
  'invoiceNumber': String?,
  'invoiceDate': DateTime?,
  'confidence': double,
  'rawText': String,
  'message': String
}
```
