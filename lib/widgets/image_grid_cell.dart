import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:ps12_image_overview/models/image_metadata.dart';
import 'package:ps12_image_overview/di/service_locator.dart';
import 'package:ps12_image_overview/services/image_service.dart';
import 'package:ps12_image_overview/implementations/services/tercen_image_service.dart';

/// Widget that displays a single image cell in the grid.
///
/// Barcode labels are deliberately not drawn here (CR-01-10). They live in the
/// grid's pinned column header row instead, so they stay visible while the grid
/// scrolls vertically and render regardless of which rows are present in the
/// dataset or survive the active filter.
class ImageGridCell extends StatelessWidget {
  final ImageMetadata image;

  const ImageGridCell({
    super.key,
    required this.image,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Container(
        color: Colors.black,
        child: Center(
          child: _buildImage(),
        ),
      ),
    );
  }

  /// Builds the image widget - from bytes, asset path, or placeholder.
  ///
  /// Priority:
  /// 1. imageBytes - runtime-loaded images (from API + TIFF conversion)
  /// 2. imagePath - bundled asset images
  /// 3. Bytes already sitting in the service cache, read synchronously
  /// 4. Lazy-load from Tercen API and convert TIFF to PNG
  /// 5. placeholder - fallback dot pattern
  Widget _buildImage() {
    // First priority: pre-loaded image bytes
    if (image.imageBytes != null) {
      return Image.memory(
        image.imageBytes!,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholderImage();
        },
      );
    }

    // Second priority: bundled asset path
    if (image.imagePath != null) {
      return Image.asset(
        image.imagePath!,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholderImage();
        },
      );
    }

    final imageService = locator<ImageService>();
    if (imageService is TercenImageService) {
      // Third priority: paint cached bytes on this frame (CR-01-30). Routing a
      // cache hit through the FutureBuilder below would start at
      // ConnectionState.waiting and flash a spinner every rebuild - very
      // visible while panning.
      final cached = imageService.cachedImage(image.id);
      if (cached != null) {
        return Image.memory(
          cached,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return _buildErrorIndicator('Image decode failed');
          },
        );
      }

      // Fourth priority: lazy-load from Tercen API
      return FutureBuilder<Uint8List?>(
        future: imageService.fetchAndConvertImage(image.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Show loading indicator while fetching
            return Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.grey.shade400,
              ),
            );
          }

          if (snapshot.hasData && snapshot.data != null) {
            // Display converted PNG bytes
            return Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return _buildErrorIndicator('Image decode failed');
              },
            );
          }

          // Show error indicator if fetch/conversion failed
          return _buildErrorIndicator('Failed to load image');
        },
      );
    }

    // Fallback: placeholder
    return _buildPlaceholderImage();
  }

  /// Builds a placeholder image with dots pattern (similar to the reference image).
  Widget _buildPlaceholderImage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: DotPatternPainter(),
        );
      },
    );
  }

  /// Builds an error indicator overlay showing that image loading failed.
  Widget _buildErrorIndicator(String message) {
    return Stack(
      children: [
        // Background: placeholder pattern
        _buildPlaceholderImage(),
        // Foreground: error indicator
        Container(
          color: Colors.red.withValues(alpha: 0.2),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  color: Colors.red.shade300,
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.red.shade200,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  image.metadata['barcode'] as String? ?? image.id,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.red.shade100,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Custom painter that creates a dot pattern similar to the reference images.
/// Simulates microscopy/scientific imaging with scattered bright spots.
class DotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Create scattered dots that resemble the reference image
    // Pattern inspired by microscopy imaging with varying intensities
    final dots = [
      // Top-left scattered dots
      (0.15, 0.12, 2.0, 0.9),
      (0.2, 0.15, 1.5, 0.6),
      (0.12, 0.2, 2.5, 0.8),
      (0.18, 0.25, 1.8, 0.5),

      // Top-center brighter cluster
      (0.42, 0.15, 2.5, 1.0),
      (0.48, 0.18, 3.0, 0.95),
      (0.45, 0.22, 2.0, 0.7),
      (0.52, 0.2, 2.2, 0.8),

      // Top-right scattered
      (0.75, 0.15, 2.0, 0.75),
      (0.82, 0.18, 1.8, 0.6),
      (0.78, 0.23, 2.3, 0.7),

      // Middle-left
      (0.1, 0.4, 1.8, 0.6),
      (0.15, 0.45, 2.2, 0.75),
      (0.08, 0.5, 1.5, 0.5),

      // Center-right bright vertical cluster
      (0.58, 0.35, 3.0, 1.0),
      (0.62, 0.38, 2.8, 0.95),
      (0.6, 0.42, 3.2, 1.0),
      (0.58, 0.46, 2.5, 0.9),
      (0.62, 0.5, 3.0, 0.95),
      (0.6, 0.54, 2.8, 0.85),
      (0.58, 0.58, 2.5, 0.8),
      (0.62, 0.62, 2.2, 0.75),

      // Right side scattered
      (0.78, 0.45, 2.0, 0.7),
      (0.85, 0.48, 1.8, 0.6),
      (0.82, 0.52, 2.2, 0.65),

      // Bottom-left
      (0.15, 0.75, 2.0, 0.7),
      (0.2, 0.78, 1.8, 0.6),
      (0.12, 0.82, 2.3, 0.75),

      // Bottom-center scattered
      (0.45, 0.75, 2.2, 0.8),
      (0.5, 0.78, 1.9, 0.65),
      (0.48, 0.82, 2.5, 0.7),

      // Bottom-right
      (0.75, 0.75, 2.0, 0.75),
      (0.82, 0.78, 1.7, 0.6),
      (0.78, 0.85, 2.1, 0.7),

      // Additional scattered faint dots
      (0.25, 0.35, 1.5, 0.4),
      (0.35, 0.55, 1.3, 0.35),
      (0.7, 0.35, 1.6, 0.45),
      (0.3, 0.65, 1.4, 0.4),
      (0.68, 0.68, 1.5, 0.45),
    ];

    for (final dot in dots) {
      final x = size.width * dot.$1;
      final y = size.height * dot.$2;
      final radius = dot.$3;
      final opacity = dot.$4;

      paint.color = Colors.white.withValues(alpha: opacity);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
