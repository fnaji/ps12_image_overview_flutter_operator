import 'dart:async';
import 'dart:typed_data';

import 'package:ps12_image_overview/models/filter_criteria.dart';
import 'package:ps12_image_overview/models/image_collection.dart';
import 'package:ps12_image_overview/models/image_metadata.dart';
import 'package:ps12_image_overview/models/image_metadata_impl.dart';
import 'package:ps12_image_overview/services/image_service.dart';
import 'package:ps12_image_overview/utils/image_bytes_cache.dart';
import 'package:ps12_image_overview/utils/request_deduplicator.dart';
import 'package:ps12_image_overview/utils/tiff_converter.dart';
import 'package:ps12_image_overview/utils/document_id_resolver.dart';
import 'package:sci_tercen_client/sci_client_service_factory.dart';
import 'package:sci_tercen_client/sci_client.dart' show FileDocument;

/// Real implementation of ImageService using Tercen platform API.
///
/// This service fetches TIFF images from Tercen's file storage, converts them
/// to PNG format using the WASM-based TiffConverter, and provides them to the UI.
///
/// Features:
/// - Lazy loading: Fetches metadata first, downloads images on-demand
/// - Caching: Stores converted PNG bytes to avoid redundant conversions
/// - Error handling: Gracefully handles network and conversion errors
/// - Request throttling: Limits concurrent downloads to prevent server overload
class TercenImageService implements ImageService {
  final ServiceFactory _serviceFactory;
  final ImageBytesCache _cache;
  final DocumentIdResolver _documentIdResolver;

  /// Cached image metadata loaded on startup
  List<ImageMetadata>? _imageMetadata;

  /// Maximum number of concurrent image downloads
  static const int _maxConcurrentDownloads = 3;

  /// Current number of active downloads
  int _activeDownloads = 0;

  /// Queue of pending download requests
  final List<_DownloadRequest> _downloadQueue = [];

  /// Collapses repeated requests for the same image onto one download
  /// (CR-01-31), so widget rebuilds during loading cannot queue duplicates.
  final RequestDeduplicator<Uint8List?> _inFlight =
      RequestDeduplicator<Uint8List?>();

  TercenImageService(
    this._serviceFactory, {
    String? taskId,
    String? workflowId,
    String? stepId,
    String? devZipFileId,
  })  : _cache = ImageBytesCache(),
        _documentIdResolver = DocumentIdResolver(
          serviceFactory: _serviceFactory,
          taskId: taskId,
          workflowId: workflowId,
          stepId: stepId,
          devZipFileId: devZipFileId,
        );

  @override
  Future<ImageCollection> loadImages() async {
    try {
      print('📋 TercenImageService.loadImages() started');

      // Use DocumentIdResolver to get both document IDs
      final resolvedIds = await _documentIdResolver.resolveDocumentId();

      if (resolvedIds == null || !resolvedIds.hasAnyId) {
        // No document ID found, use mock data
        print('⚠️ No document IDs resolved, using mock data');
        _imageMetadata = _createMockMetadata();
        return ImageCollection(images: _imageMetadata!);
      }

      print('✓ Resolved IDs: $resolvedIds');

      // Get services from Tercen ServiceFactory
      final fileService = _serviceFactory.fileService;
      final documentService = _serviceFactory.documentService;

      // Fetch the file document with fallback logic
      // Strategy 1: Try documentId first (PRIMARY)
      // Strategy 2: If that fails, try id column value (FALLBACK)
      List<FileDocument> files;
      FileDocument? zipFile;

      if (resolvedIds.documentId != null) {
        // First, try to resolve via DocumentService to see what type it is
        try {
          print('   🔍 Attempting to resolve documentId via DocumentService: ${resolvedIds.documentId}');
          final doc = await documentService.get(resolvedIds.documentId!);
          print('   ✓ Successfully resolved document');
          print('   📄 Document type: ${doc.runtimeType}');
          print('   📄 Document kind: ${doc.kind}');
          print('   📄 Document name: ${doc.name}');

          if (doc is FileDocument) {
            print('   ✓ Document is a FileDocument, using it directly');
            zipFile = doc;
          } else {
            print('   ⚠️ Document is not a FileDocument (it is ${doc.runtimeType})');
            // Try FileService as fallback
            print('   🔄 Attempting FileService.get() as fallback');
            try {
              zipFile = await fileService.get(resolvedIds.documentId!);
              print('   ✓ FileService fallback succeeded: ${zipFile.name}');
            } catch (e2) {
              print('   ✗ FileService fallback also failed: $e2');
            }
          }
        } catch (e) {
          print('   ✗ Error resolving documentId via DocumentService: $e');

          // Try FileService directly as fallback
          try {
            print('   🔄 Attempting to load file with FileService.get(): ${resolvedIds.documentId}');
            zipFile = await fileService.get(resolvedIds.documentId!);
            print('   ✓ Successfully loaded file with FileService: ${zipFile.name}');
          } catch (e2) {
            print('   ✗ Error loading file with FileService ${resolvedIds.documentId}: $e2');

            // Try fallback to id column value
            if (resolvedIds.id != null) {
              try {
                print('   🔄 Attempting fallback to id column value via DocumentService: ${resolvedIds.id}');
                final idDoc = await documentService.get(resolvedIds.id!);
                print('   ✓ Successfully resolved id via DocumentService');
                print('   📄 ID document type: ${idDoc.runtimeType}');

                if (idDoc is FileDocument) {
                  print('   ✓ ID document is a FileDocument, using it');
                  zipFile = idDoc;
                } else {
                  print('   ⚠️ ID document is not a FileDocument');
                }
              } catch (e3) {
                print('   ✗ Error resolving id ${resolvedIds.id}: $e3');
              }
            }
          }
        }
      } else if (resolvedIds.id != null) {
        // No documentId, try id directly via DocumentService
        try {
          print('   🔍 Attempting to resolve id via DocumentService: ${resolvedIds.id}');
          final doc = await documentService.get(resolvedIds.id!);
          print('   ✓ Successfully resolved id document');
          print('   📄 Document type: ${doc.runtimeType}');

          if (doc is FileDocument) {
            print('   ✓ ID is a FileDocument, using it');
            zipFile = doc;
          } else {
            print('   ⚠️ ID is not a FileDocument (it is ${doc.runtimeType})');
          }
        } catch (e) {
          print('   ✗ Error resolving id ${resolvedIds.id}: $e');
        }
      }

      // If documentId/id strategies failed, try workflow/step file search
      if (zipFile == null) {
        print('⚠️ DocumentId strategies failed, trying workflow/step file search...');
        final docIdFromWorkflow = await _documentIdResolver.tryFindFilesByWorkflowStep();

        if (docIdFromWorkflow != null) {
          try {
            print('   🔍 Attempting to load file from workflow/step search: $docIdFromWorkflow');
            zipFile = await fileService.get(docIdFromWorkflow);
            print('   ✓ Successfully loaded file via workflow/step search: ${zipFile.name}');
          } catch (e) {
            print('   ✗ Error loading file from workflow/step search: $e');
          }
        }
      }

      // Final fallback to mock data
      if (zipFile == null) {
        print('⚠️ All file loading strategies failed, falling back to mock data');
        _imageMetadata = _createMockMetadata();
        return ImageCollection(images: _imageMetadata!);
      }

      files = [zipFile];

      // Process files - handle both individual TIFF files and zip archives
      final List<ImageMetadata> allMetadata = [];

      for (final file in files) {
        if (_isZipFile(file.name)) {
          // Handle zip file - list contents and create metadata for each TIFF
          final zipEntries = await _loadImagesFromZip(file.id, fileService);
          allMetadata.addAll(zipEntries);
        } else if (_isTiffFile(file.name)) {
          // Handle individual TIFF file
          final metadata = TiffConverter.parseFilename(file.name);

          allMetadata.add(ImageMetadataImpl(
            id: file.id,
            cycle: metadata['pumpCycle'] as int? ?? 0,
            exposureTime: metadata['temperature'] as int? ?? 0,  // T parameter (exposureTime)
            row: (metadata['well'] as int? ?? 1) - 1,  // Well: W1 = row 0, W2 = row 1, etc.
            column: 0,  // Will be set after collecting all barcodes
            imagePath: null,
            imageBytes: null, // Lazy-loaded
            timestamp: DateTime.now(),
            metadata: {
              'fileDocumentId': file.id,
              'filename': file.name,
              'isZipEntry': false,
              'barcode': metadata['barcode'] as String? ?? '',
              'filter': metadata['filter'] as int? ?? 0,
              'imageNumber': metadata['imageNumber'] as int? ?? 0,
              'array': metadata['array'] as int? ?? 0,  // A parameter (actual temperature)
            },
          ));
        }
      }

      // Create barcode to column index mapping
      final barcodes = <String>{};
      for (final img in allMetadata) {
        final barcode = img.metadata['barcode'] as String? ?? '';
        if (barcode.isNotEmpty) {
          barcodes.add(barcode);
        }
      }
      final barcodeList = barcodes.toList()..sort();
      final barcodeToColumn = <String, int>{};
      for (var i = 0; i < barcodeList.length; i++) {
        barcodeToColumn[barcodeList[i]] = i;
      }

      // Update column indices based on barcode mapping and create final metadata list
      final List<ImageMetadata> finalMetadata = [];
      for (final img in allMetadata) {
        final barcode = img.metadata['barcode'] as String? ?? '';
        final columnIndex = barcodeToColumn[barcode] ?? 0;

        final imgImpl = img as ImageMetadataImpl;
        finalMetadata.add(ImageMetadataImpl(
          id: imgImpl.id,
          cycle: imgImpl.cycle,
          exposureTime: imgImpl.exposureTime,
          row: imgImpl.row,
          column: columnIndex,  // Set column based on barcode
          imagePath: imgImpl.imagePath,
          imageBytes: imgImpl.imageBytes,
          timestamp: imgImpl.timestamp,
          metadata: imgImpl.metadata,
        ));
      }

      _imageMetadata = finalMetadata;
      print('Loaded ${_imageMetadata!.length} image metadata entries from Tercen');
      print('Found ${barcodeList.length} unique barcodes (columns): $barcodeList');

      return ImageCollection(images: _imageMetadata!);
    } catch (e, stackTrace) {
      print('Error loading images from Tercen: $e');
      print(stackTrace);
      // Return empty collection on error
      return ImageCollection(images: []);
    }
  }

  @override
  Future<ImageCollection> filterImages(FilterCriteria criteria) async {
    // Ensure metadata is loaded
    if (_imageMetadata == null) {
      await loadImages();
    }

    if (_imageMetadata == null || _imageMetadata!.isEmpty) {
      return ImageCollection(images: []);
    }

    // Client-side filtering (metadata already loaded)
    final filtered = _imageMetadata!.where((image) {
      // Filter by cycle if specified
      if (criteria.cycle != null &&
          image.cycle != criteria.cycle) {
        return false;
      }

      // Filter by exposure time if specified
      if (criteria.exposureTime != null &&
          image.exposureTime != criteria.exposureTime) {
        return false;
      }

      return true;
    }).toList();

    return ImageCollection(images: filtered);
  }

  /// Fetches and converts a TIFF image to PNG bytes.
  ///
  /// This method is intended to be called by the UI layer when an image
  /// needs to be displayed. It checks the cache first, then downloads
  /// and converts the TIFF if necessary.
  ///
  /// Supports both individual files and files within zip archives.
  ///
  /// Uses request throttling to prevent overwhelming the Tercen server with
  /// concurrent downloads. Maximum of 3 concurrent downloads allowed.
  ///
  /// Returns null if the download or conversion fails.
  Future<Uint8List?> fetchAndConvertImage(String imageId) {
    // Check cache first
    final cached = _cache.get(imageId);
    if (cached != null) {
      return Future.value(cached);
    }

    // Share one download between all callers asking for this image
    // (CR-01-31).
    return _inFlight.run(imageId, () {
      final completer = Completer<Uint8List?>();
      final request = _DownloadRequest(imageId, completer);

      // Add to queue and try to process
      _downloadQueue.add(request);
      _processQueue();

      // Wait for the download to complete
      return completer.future;
    });
  }

  /// Returns already-converted PNG bytes for [imageId], or null if not cached.
  ///
  /// Synchronous by design (CR-01-30): lets the UI paint a cached image on the
  /// current frame instead of routing through a FutureBuilder, which would
  /// start at ConnectionState.waiting and flash a spinner on every rebuild.
  Uint8List? cachedImage(String imageId) => _cache.get(imageId);

  /// Processes the download queue, respecting the concurrency limit.
  void _processQueue() {
    // Process as many requests as we can within the concurrency limit
    while (_activeDownloads < _maxConcurrentDownloads && _downloadQueue.isNotEmpty) {
      final request = _downloadQueue.removeAt(0);
      _activeDownloads++;

      // Start the download (fire and forget)
      _downloadAndConvertImage(request).then((_) {
        _activeDownloads--;
        // Process next item in queue
        _processQueue();
      });
    }
  }

  /// Actually downloads and converts a single image.
  Future<void> _downloadAndConvertImage(_DownloadRequest request) async {
    try {
      // Find the image metadata to determine if it's a zip entry
      final imageMetadata = _imageMetadata?.firstWhere(
        (img) => img.id == request.imageId,
        orElse: () => throw StateError('Image metadata not found for ${request.imageId}'),
      );

      if (imageMetadata == null) {
        throw StateError('Image metadata not loaded');
      }

      final fileService = _serviceFactory.fileService;
      final Stream<List<int>> tiffStream;

      final isZipEntry = imageMetadata.metadata['isZipEntry'] as bool? ?? false;

      if (isZipEntry) {
        // Download from zip archive
        final zipFileId = imageMetadata.metadata['zipFileId'] as String?;
        final entryPath = imageMetadata.metadata['zipEntryPath'] as String?;

        if (zipFileId == null || entryPath == null) {
          print('Missing zip metadata for image ${request.imageId}');
          request.completer.complete(null);
          return;
        }

        tiffStream = fileService.downloadZipEntry(zipFileId, entryPath);
      } else {
        // Download regular file
        final fileDocumentId = imageMetadata.metadata['fileDocumentId'] as String?;

        if (fileDocumentId == null) {
          print('Missing fileDocumentId for image ${request.imageId} (possibly mock data)');
          request.completer.complete(null);
          return;
        }

        tiffStream = fileService.download(fileDocumentId);
      }

      // Collect stream into bytes with timeout
      final tiffBytes = await _collectStreamBytes(tiffStream)
          .timeout(const Duration(seconds: 30));

      // Convert TIFF to PNG
      final pngBytes = TiffConverter.convertToPng(tiffBytes);

      if (pngBytes != null) {
        // Cache the converted PNG
        _cache.put(request.imageId, pngBytes);
      } else {
        print('⚠️ Failed to convert TIFF to PNG for image ${request.imageId}');
      }

      request.completer.complete(pngBytes);
    } on TimeoutException {
      print('⏱️ Timeout downloading image ${request.imageId} (exceeded 30 seconds)');
      request.completer.complete(null);
    } on StateError catch (e) {
      print('⚠️ Image metadata error for ${request.imageId}: $e');
      request.completer.complete(null);
    } catch (e, stackTrace) {
      final errorMsg = e.toString().toLowerCase();

      // Provide specific error messages based on error type
      if (errorMsg.contains('format') || errorMsg.contains('invalid') ||
          errorMsg.contains('corrupt')) {
        print('❌ Corrupted image file ${request.imageId}: $e');
      } else if (errorMsg.contains('not found') || errorMsg.contains('404')) {
        print('❌ Image file not found ${request.imageId}: $e');
      } else if (errorMsg.contains('zip')) {
        print('❌ ZIP entry error for ${request.imageId}: $e');
        print('   The ZIP archive may be corrupted or the entry path may be invalid');
      } else {
        print('❌ Error fetching image ${request.imageId}: $e');
        print('   Stack trace: $stackTrace');
      }

      request.completer.complete(null);
    }
  }

  /// Collects a stream of bytes into a single Uint8List.
  Future<Uint8List> _collectStreamBytes(Stream<List<int>> stream) async {
    final chunks = await stream.toList();
    final totalLength = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final bytes = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in chunks) {
      bytes.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return bytes;
  }

  /// Creates mock metadata for development/testing when Tercen context is unavailable.
  List<ImageMetadata> _createMockMetadata() {
    final images = <ImageMetadata>[];

    const cycles = [124, 125, 126, 127];
    const exposureTimes = [100, 150, 200, 250];
    const rows = [0, 1, 2, 3];
    const columns = [0, 1, 2];

    var id = 0;
    for (final cycle in cycles) {
      for (final exposure in exposureTimes) {
        for (final row in rows) {
          for (final column in columns) {
            // Simulate filtering: column 2 only available for exposure 250
            if (column == 2 && exposure != 250) {
              continue;
            }

            images.add(ImageMetadataImpl(
              id: 'mock_$id',
              cycle: cycle,
              exposureTime: exposure,
              row: row,
              column: column,
              imagePath: null,
              imageBytes: null,
              timestamp: DateTime.now(),
              metadata: const {'mock': true},
            ));
            id++;
          }
        }
      }
    }

    return images;
  }

  /// Returns cache statistics for debugging
  Map<String, dynamic> getCacheStats() {
    return {
      'cached_images': _cache.length,
      'current_size_mb': _cache.currentSizeMB.toStringAsFixed(2),
      'max_size_mb': _cache.maxSizeMB.toStringAsFixed(2),
      'cache_usage_percent':
          ((_cache.currentSizeMB / _cache.maxSizeMB) * 100).toStringAsFixed(1),
    };
  }

  /// Clears the image cache
  void clearCache() {
    _cache.clear();
    print('Image cache cleared');
  }

  /// Loads images from a zip archive
  Future<List<ImageMetadata>> _loadImagesFromZip(
      String zipFileId, dynamic fileService) async {
    final images = <ImageMetadata>[];

    try {
      // List all entries in the zip file
      final zipEntries = await fileService.listZipContents(zipFileId);

      print('Found ${zipEntries.length} entries in zip file $zipFileId');

      if (zipEntries.isEmpty) {
        print('⚠️ ZIP file is empty or could not be read');
        return images;
      }

      // Filter for TIFF files and create metadata
      for (final entry in zipEntries) {
        final entryName = entry.name as String;

        if (_isTiffFile(entryName)) {
          // Parse filename to extract metadata
          final metadata = TiffConverter.parseFilename(entryName);

          // Generate unique ID combining zip file ID and entry path
          final uniqueId = '${zipFileId}_${entryName.replaceAll('/', '_')}';

          images.add(ImageMetadataImpl(
            id: uniqueId,
            cycle: metadata['pumpCycle'] as int? ?? 0,
            exposureTime: metadata['temperature'] as int? ?? 0,  // T parameter (exposureTime)
            row: (metadata['well'] as int? ?? 1) - 1,  // Well: W1 = row 0, W2 = row 1, etc.
            column: 0,  // Will be set in loadImages() after collecting all barcodes
            imagePath: null,
            imageBytes: null, // Lazy-loaded
            timestamp: DateTime.now(),
            metadata: {
              'zipFileId': zipFileId,
              'zipEntryPath': entryName,
              'filename': entryName,
              'isZipEntry': true,
              'barcode': metadata['barcode'] as String? ?? '',
              'filter': metadata['filter'] as int? ?? 0,
              'imageNumber': metadata['imageNumber'] as int? ?? 0,
              'array': metadata['array'] as int? ?? 0,  // A parameter (actual temperature)
            },
          ));
        }
      }

      print('Extracted ${images.length} TIFF files from zip');

      if (images.isEmpty && zipEntries.isNotEmpty) {
        print('⚠️ No TIFF files found in ZIP (${zipEntries.length} total entries)');
      }
    } on TimeoutException {
      print('❌ Timeout reading ZIP file: Operation took too long');
    } catch (e, stackTrace) {
      final errorMsg = e.toString().toLowerCase();

      // Provide specific error messages based on error type
      if (errorMsg.contains('format') || errorMsg.contains('invalid') ||
          errorMsg.contains('corrupt') || errorMsg.contains('magic')) {
        print('❌ ZIP file appears to be corrupted or invalid: $e');
        print('   Please check that the uploaded file is a valid ZIP archive');
      } else if (errorMsg.contains('permission') || errorMsg.contains('access')) {
        print('❌ Permission error accessing ZIP file: $e');
        print('   The file may be locked or access rights are insufficient');
      } else if (errorMsg.contains('not found') || errorMsg.contains('404')) {
        print('❌ ZIP file not found: $e');
        print('   The file may have been deleted or moved');
      } else {
        print('❌ Error loading images from ZIP: $e');
        print('   Stack trace: $stackTrace');
      }
    }

    return images;
  }

  /// Checks if a filename is a zip file
  bool _isZipFile(String filename) {
    final lowerName = filename.toLowerCase();
    return lowerName.endsWith('.zip');
  }

  /// Checks if a filename is a TIFF file
  bool _isTiffFile(String filename) {
    final lowerName = filename.toLowerCase();
    return lowerName.endsWith('.tif') || lowerName.endsWith('.tiff');
  }
}

/// Internal class to represent a download request in the queue.
class _DownloadRequest {
  final String imageId;
  final Completer<Uint8List?> completer;

  _DownloadRequest(this.imageId, this.completer);
}
