# PS12 Image Overview - Flutter Application

A Flutter application for displaying and filtering PamGene TIFF images from the Tercen platform with real-time TIFF to PNG conversion.

## Features 

- **Image Grid Display**: Dynamic grid layout showing images with row numbers and column IDs
- **Filter Controls**:
  - Cycle filter dropdown (dynamically populated from data)
  - Exposure Time filter dropdown (dynamically populated from data)
- **Tercen Integration**: Real integration with Tercen platform API using sci_tercen_client
- **TIFF Support**: Client-side TIFF to PNG conversion using WebAssembly
- **Zip Archive Support**: Automatically extracts and displays TIFF images from zip files
- **Lazy Loading**: Metadata loaded on startup, images fetched on-demand
- **Smart Caching**: 50MB LRU cache for converted PNG bytes
- **Theme Support**: Light/dark mode toggle
- **Clean Architecture**: Service abstraction, dependency injection, and state management

## Architecture

This project follows clean architecture principles:

- **Models**: Abstract interfaces and concrete implementations
- **Services**: Abstract service interfaces for data operations
- **Implementations**: Mock service implementations (ready for real backend integration)
- **Providers**: State management using Provider pattern
- **Screens**: UI screens
- **Widgets**: Reusable UI components
- **DI**: Dependency injection using GetIt

## Getting Started

### Prerequisites

- Flutter SDK (^3.10.1)
- Dart SDK
- Access to Tercen platform (for real data integration)

### Installation

1. Install dependencies:
```bash
flutter pub get
```

### Running the Application

#### Option 1: Mock Data (Local Development)
Run with mock data for development and testing (requires USE_MOCKS=true):
```bash
# Web
flutter run -d chrome --dart-define=USE_MOCKS=true

# Desktop (Windows)
flutter run -d windows --dart-define=USE_MOCKS=true
```

#### Option 2: Tercen Integration - Development Mode (Local Testing with Real Data)

Run with real Tercen data using explicit token and document ID for local testing:

**Default Document ID**: `9d8fdc8ec1d6f203834caa17f10038cb`

**For Windows PowerShell:**
```powershell
flutter run -d chrome `
  --dart-define=USE_MOCKS=false `
  --dart-define=DEV_TOKEN=<your-tercen-token> `
  --dart-define=DEV_SERVER_URL=https://stage.tercen.com `
  --dart-define=DEV_ZIP_FILE_ID=9d8fdc8ec1d6f203834caa17f10038cb `
  --web-browser-flag="--disable-web-security" `
  --web-browser-flag="--user-data-dir=C:\temp\chrome-dev-session"
```

**For Linux/Mac (bash/zsh):**
```bash
flutter run -d chrome \
  --dart-define=USE_MOCKS=false \
  --dart-define=DEV_TOKEN=<your-tercen-token> \
  --dart-define=DEV_SERVER_URL=https://stage.tercen.com \
  --dart-define=DEV_ZIP_FILE_ID=9d8fdc8ec1d6f203834caa17f10038cb \
  --web-browser-flag="--disable-web-security" \
  --web-browser-flag="--user-data-dir=/tmp/chrome-dev-session"
```

**How to get your Tercen token:**

1. Log in to <https://stage.tercen.com>
2. Open browser developer tools (F12)
3. Go to Console tab
4. Run: `localStorage.getItem('tercen.token')`
5. Copy the token (without quotes)

> **Important**: The `--disable-web-security` flag is needed for local development to bypass CORS restrictions. This is only for development - in production, the app will be deployed to a Tercen-allowed domain.

#### Option 3: Tercen Integration - Custom Document ID
Override the default document ID with a custom one:

**Windows PowerShell:**
```powershell
flutter run -d chrome --dart-define=USE_MOCKS=false --dart-define=TERCEN_TOKEN=<your-token> --dart-define=SERVICE_URI=https://stage.tercen.com --dart-define=DEV_ZIP_FILE_ID=<your-document-id>
```

**Linux/Mac:**
```bash
flutter run -d chrome \
  --dart-define=USE_MOCKS=false \
  --dart-define=TERCEN_TOKEN=<your-token> \
  --dart-define=SERVICE_URI=https://stage.tercen.com \
  --dart-define=DEV_ZIP_FILE_ID=<your-document-id>
```

#### Option 4: Tercen Integration - Production Mode
Run in production with workflow and step IDs:

**Windows PowerShell:**
```powershell
flutter run -d chrome --dart-define=USE_MOCKS=false --dart-define=TERCEN_TOKEN=<your-token> --dart-define=SERVICE_URI=https://tercen.com --dart-define=WORKFLOW_ID=<workflow-id> --dart-define=STEP_ID=<step-id>
```

**Linux/Mac:**
```bash
flutter run -d chrome \
  --dart-define=USE_MOCKS=false \
  --dart-define=TERCEN_TOKEN=<your-token> \
  --dart-define=SERVICE_URI=https://tercen.com \
  --dart-define=WORKFLOW_ID=<workflow-id> \
  --dart-define=STEP_ID=<step-id>
```

## Project Structure

```
lib/
├── di/
│   └── service_locator.dart                    # Dependency injection setup
├── models/
│   ├── image_metadata.dart                     # Abstract image metadata interface
│   ├── image_metadata_impl.dart                # Concrete implementation
│   ├── image_collection.dart                   # Collection model
│   └── filter_criteria.dart                    # Filter criteria model
├── services/
│   └── image_service.dart                      # Abstract service interface
├── implementations/
│   └── services/
│       ├── mock_image_service.dart             # Mock service implementation
│       └── tercen_image_service.dart           # Real Tercen API implementation
├── providers/
│   ├── image_overview_provider.dart            # State management
│   └── theme_provider.dart                     # Theme state management
├── screens/
│   └── image_overview_screen.dart              # Main screen
├── widgets/
│   └── image_grid_cell.dart                    # Grid cell widget
├── utils/
│   ├── image_bytes_cache.dart                  # LRU cache for PNG bytes
│   └── tiff_converter.dart                     # TIFF to PNG conversion
└── main.dart                                    # Application entry point
```

## Key Dependencies

- `provider: ^6.1.1` - State management
- `get_it: ^7.6.4` - Service locator for dependency injection
- `image: ^4.2.0` - TIFF to PNG conversion (runtime)
- `sci_tercen_client: 1.7.0` - Official Tercen platform client library

## How It Works

### Architecture Overview

1. **Service Factory Pattern**: Uses Tercen's ServiceFactory for API access
2. **Three Operational Modes**:
   - **Mock Mode**: Uses hardcoded mock data (default)
   - **Development Mode**: Uses hardcoded zip file document ID
   - **Production Mode**: Queries files by workflow and step IDs

3. **Data Flow**:
   ```
   Tercen Platform API
       ↓ (fetch metadata + TIFF bytes)
   TercenImageService
       ↓ (parse filenames, extract metadata)
   TiffConverter (WASM)
       ↓ (convert TIFF → PNG)
   ImageBytesCache (50MB LRU)
       ↓ (cached PNG bytes)
   UI Layer (ImageOverviewProvider)
   ```

### Lazy Loading Strategy

- **Startup**: Loads image metadata only (fast)
- **On-Demand**: Downloads and converts TIFF images when displayed
- **Caching**: Stores converted PNG bytes (50MB max, LRU eviction)

### Zip File Support

The application automatically handles zip archives:
1. Detects `.zip` files from Tercen
2. Lists all entries in the zip using `listZipContents()`
3. Extracts TIFF files individually using `downloadZipEntry()`
4. No need to download entire zip file

## Configuration

### Environment Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `USE_MOCKS` | Enable mock data mode | `true` | `false` |
| `DEV_TOKEN` | Tercen authentication token (local dev) | - | `eyJ0eXAi...` |
| `DEV_SERVER_URL` | Tercen server URL (local dev) | - | `https://stage.tercen.com` |
| `DEV_ZIP_FILE_ID` | Document ID for development | `9d8fdc8ec1d6f203834caa17f10038cb` | `abc123...` |
| `WORKFLOW_ID` | Production workflow ID | - | `workflow123` |
| `STEP_ID` | Production step ID | - | `step456` |

### Hardcoded Development ID

The default zip file document ID is hardcoded in [lib/implementations/services/tercen_image_service.dart:46](lib/implementations/services/tercen_image_service.dart#L46):

```dart
defaultValue: '9d8fdc8ec1d6f203834caa17f10038cb'
```

You can change this directly in the code or override it with `--dart-define=DEV_ZIP_FILE_ID=<id>`.

## Troubleshooting

### CORS Errors (Local Development)

**Error**: `Access to XMLHttpRequest ... has been blocked by CORS policy`

**Cause**: Web browsers block cross-origin requests from `localhost` to external domains for security.

**Solution**: Run Chrome with CORS disabled (development only):
```powershell
flutter run -d chrome --dart-define=USE_MOCKS=false --dart-define=TERCEN_TOKEN=<your-token> --dart-define=SERVICE_URI=https://stage.tercen.com --web-browser-flag="--disable-web-security" --web-browser-flag="--user-data-dir=C:\temp\chrome-dev-session"
```

**Important Notes**:
- Only use `--disable-web-security` for local development
- Close all Chrome instances before running this command
- In production (deployed to Tercen domain), CORS is not an issue

### Token Expiration

If you see authentication errors, your token may have expired. Generate a new token from Tercen and update the `TERCEN_TOKEN` environment variable.

### TIFF Conversion Failures
If images fail to display:
1. Check browser console for conversion errors
2. Verify TIFF files are valid and accessible
3. Check filename parsing in TiffConverter.parseFilename()

### Memory Issues
The cache is limited to 50MB. If you're loading many large images:
- Reduce cache size in [lib/utils/image_bytes_cache.dart:21](lib/utils/image_bytes_cache.dart#L21)
- Clear cache manually using the service's `clearCache()` method

## Future Enhancements

- Image selection and export
- Zoom and detail views
- Advanced filtering (by row, column, etc.)
- Batch download functionality
- Image comparison mode

## Technical Specification

See [FLUTTER_TECHNICAL_SPECIFICATION.md](FLUTTER_TECHNICAL_SPECIFICATION.md) for detailed architecture and implementation guidelines.