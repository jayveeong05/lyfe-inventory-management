# OCR Invoice Data Extraction Feature

## Overview

The OCR (Optical Character Recognition) feature automatically extracts invoice numbers and dates from uploaded PDF or image files using Google ML Kit Text Recognition. This reduces manual data entry and improves accuracy.

**Current Status**: Due to PDF rendering package compatibility issues with newer Flutter versions, the feature currently works with image files (PNG, JPG, JPEG). PDF support is temporarily disabled but can be restored with compatible packages.

## Features

- **Image File Support**: Directly processes PNG, JPG, and JPEG image files
- **PDF Support (Temporarily Disabled)**: PDF to image conversion temporarily unavailable due to package compatibility
- **Text Recognition**: Uses Google ML Kit for on-device text recognition
- **Smart Data Parsing**: Extracts invoice numbers and dates using multiple regex patterns
- **Confidence Scoring**: Provides confidence levels for extracted data
- **User Validation**: Shows confirmation dialog for low-confidence results
- **Manual Override**: Users can always edit or manually enter data

## How It Works

### 1. User Workflow
1. User uploads a PDF invoice file
2. "Extract Invoice Data" button appears
3. User clicks the button to start OCR extraction
4. System processes the PDF and extracts data
5. Form fields are auto-populated with extracted data
6. User reviews and corrects data if needed

### 2. Technical Process
1. **PDF Conversion**: First page of PDF is converted to PNG image
2. **OCR Processing**: Google ML Kit processes the image to extract text
3. **Data Parsing**: Regex patterns search for invoice numbers and dates
4. **Confidence Calculation**: System calculates confidence based on matches found
5. **User Interaction**: High confidence results auto-fill, low confidence shows dialog

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

- `google_ml_kit: ^0.18.0` - Text recognition
- `pdf_render: ^1.4.0` - PDF to image conversion
- `path_provider: ^2.1.1` - Temporary file storage
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
