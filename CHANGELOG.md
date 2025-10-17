# Changelog

All notable changes to the Inventory Management System will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.22] - 2025-10-17

### Fixed
- **Monthly Inventory Activity - Critical UI Fixes**
  - Fixed Flutter rendering exception caused by hairline border + borderRadius conflict
  - Resolved missing 98 Inch row in size breakdown table
  - Eliminated `BorderSide(width: 0.0)` with non-zero BorderRadius causing rendering failures
  - Implemented conditional border logic: no border for last row, normal border for other rows

### Changed
- **Size Breakdown Table Rendering**
  - Updated border styling to prevent Flutter rendering conflicts
  - Improved table row display logic for better compatibility
  - Enhanced data integrity verification across all panel sizes

### Verified
- All panel sizes (65", 75", 86", 98") now display correctly in size breakdown
- Remaining item counts match summary totals (45 items total)
- No more Flutter rendering exceptions in monthly inventory reports
- Complete data visibility without missing rows or display issues

## [2.0.21] - 2025-10-16

### Added
- **Monthly Inventory Activity Feature**
  - Comprehensive monthly reporting system with advanced analytics
  - Size breakdown analysis for panel dimensions
  - Category breakdown with dynamic processing
  - Hierarchical data organization (category → size → items)
  - Performance optimization with caching and batch processing

### Fixed
- **UI/UX Improvements**
  - Resolved horizontal scrolling issues in size breakdown table
  - Implemented responsive table layout with proper flex ratios
  - Fixed text wrapping in table headers
  - Enhanced mobile compatibility

### Performance
- **Optimization Enhancements**
  - 5-minute cache for cumulative calculations
  - Batch processing for large datasets (500-item batches)
  - N+1 query prevention with batch lookups
  - Memory-efficient data processing

## [2.0.20] - 2025-10-15

### Added
- **Enhanced Data Processing**
  - Smart data separation for summary vs breakdown calculations
  - Cumulative remaining calculations from beginning until selected month
  - Dynamic category analysis with proper filtering
  - Detailed item tracking with drill-down capability

### Fixed
- **Data Quality Improvements**
  - Fixed blank rows in size breakdown by excluding "Others" category
  - Corrected remaining amount calculations
  - Improved data consistency across different report sections

## [2.0.19] - 2025-10-14

### Added
- **Admin Dashboard Integration**
  - Admin users now land directly on admin dashboard
  - Enhanced user dashboard with welcome sections
  - Integrated core navigation for all user types
  - Personalized user experience improvements

### Fixed
- **Status System Corrections**
  - Fixed PO and transaction status mismatch
  - Corrected invoice upload status handling
  - Added data migration utility for status corrections

## Previous Versions

See README.md for complete version history from v1.0.0 to v2.0.18.

---

## Types of Changes

- **Added** for new features
- **Changed** for changes in existing functionality
- **Deprecated** for soon-to-be removed features
- **Removed** for now removed features
- **Fixed** for any bug fixes
- **Security** for vulnerability fixes
- **Performance** for performance improvements
- **Verified** for confirmed working features
