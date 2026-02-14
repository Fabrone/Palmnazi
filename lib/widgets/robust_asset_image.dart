import 'package:flutter/material.dart';

/// A robust image widget that handles asset images with proper loading and error states
class RobustAssetImage extends StatelessWidget {
  final String imagePath;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? errorWidget;
  final Widget? loadingWidget;
  final Color? fallbackColor;
  final IconData? fallbackIcon;

  const RobustAssetImage({
    super.key,
    required this.imagePath,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorWidget,
    this.loadingWidget,
    this.fallbackColor,
    this.fallbackIcon,
  });

  /// Ensure the path is correct for asset loading
  String _getCorrectAssetPath(String path) {
    // Remove any leading slashes
    path = path.replaceFirst(RegExp(r'^/+'), '');
    
    // If it already starts with 'assets/', use it as is
    if (path.startsWith('assets/')) {
      return path;
    }
    
    // If it starts with 'images/', prepend 'assets/'
    if (path.startsWith('images/')) {
      return 'assets/$path';
    }
    
    // If it starts with 'cities/', 'channels/', or 'places/', prepend 'assets/images/'
    if (path.startsWith('cities/') || 
        path.startsWith('channels/') || 
        path.startsWith('places/')) {
      return 'assets/images/$path';
    }
    
    // For standalone files like 'logo.png', prepend 'assets/images/'
    if (!path.contains('/')) {
      return 'assets/images/$path';
    }
    
    // Otherwise, assume it needs the full 'assets/images/' prefix
    return 'assets/images/$path';
  }

  @override
  Widget build(BuildContext context) {
    final String assetPath = _getCorrectAssetPath(imagePath);

    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      // Loading builder for progressive loading
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) {
          return child;
        }
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: frame == null 
              ? (loadingWidget ?? _buildLoadingWidget(context))
              : child,
        );
      },
      // Error builder with fallback
      errorBuilder: (context, error, stackTrace) {
        debugPrint('Error loading image: $assetPath');
        debugPrint('Error: $error');
        
        return errorWidget ?? _buildErrorWidget(context);
      },
    );
  }

  Widget _buildLoadingWidget(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: fallbackColor?.withValues(alpha: 0.3) ?? Colors.grey.withValues(alpha: 0.2),
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            fallbackColor ?? const Color(0xFF14FFEC),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            fallbackColor ?? const Color(0xFF0D7377),
            (fallbackColor ?? const Color(0xFF0D7377)).withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          fallbackIcon ?? Icons.image_not_supported_outlined,
          size: (width != null && height != null) 
              ? (width! < height! ? width! * 0.3 : height! * 0.3)
              : 60,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// Extension to make image loading easier
extension ImagePathExtension on String {
  /// Convert any image path to a proper asset path
  String toAssetPath() {
    String path = replaceFirst(RegExp(r'^/+'), '');
    
    if (path.startsWith('assets/')) {
      return path;
    }
    
    if (path.startsWith('images/')) {
      return 'assets/$path';
    }
    
    if (path.startsWith('cities/') || 
        path.startsWith('channels/') || 
        path.startsWith('places/')) {
      return 'assets/images/$path';
    }
    
    if (!path.contains('/')) {
      return 'assets/images/$path';
    }
    
    return 'assets/images/$path';
  }
}