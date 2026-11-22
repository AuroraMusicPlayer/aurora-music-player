import 'package:flutter/material.dart';

/// Artwork with a sensible fallback chain.
///
/// YouTube's `hqdefault` thumbnails are 4:3 with black bars burned in, which
/// looks broken inside a square player. `hq720` is 16:9 and fills the frame;
/// when it is missing (older uploads) we fall back to `mqdefault`.
class ArtworkImage extends StatelessWidget {
  const ArtworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.fallbackUrl,
    this.placeholderColor = const Color(0xFF1E1E1E),
  });

  final String? url;
  final String? fallbackUrl;
  final BoxFit fit;
  final Color placeholderColor;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return ColoredBox(color: placeholderColor);
    }
    return Image.network(
      url!,
      fit: fit,
      errorBuilder: (_, __, ___) {
        if (fallbackUrl == null || fallbackUrl!.isEmpty) {
          return ColoredBox(color: placeholderColor);
        }
        return Image.network(
          fallbackUrl!,
          fit: fit,
          errorBuilder: (_, __, ___) => ColoredBox(color: placeholderColor),
        );
      },
    );
  }
}

/// Convenience for a YouTube video id, applying the same fallback chain.
ArtworkImage artworkForVideo(
  String? videoId, {
  BoxFit fit = BoxFit.cover,
  Color placeholderColor = const Color(0xFF1E1E1E),
}) {
  if (videoId == null || videoId.isEmpty) {
    return ArtworkImage(url: null, fit: fit, placeholderColor: placeholderColor);
  }
  return ArtworkImage(
    url: 'https://i.ytimg.com/vi/$videoId/hq720.jpg',
    fallbackUrl: 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg',
    fit: fit,
    placeholderColor: placeholderColor,
  );
}
