part of '../main.dart';

// Photos de profil : choix d'une image, recadrage carré et compression JPEG
// (256 × 256 px, quelques dizaines de Ko) avant l'envoi à l'API.

const _photoSize = 256;
const _maxSourceBytes = 15 * 1024 * 1024;

// Renvoie la photo en base64, ou null si l'utilisateur annule.
Future<String?> _pickProfilePhoto(BuildContext context) async {
  final files = await FilePicker.pickFiles(type: FileType.image);
  if (files.isEmpty) return null;
  final source = await files.first.readAsBytes();
  if (source.length > _maxSourceBytes) {
    if (context.mounted) {
      await _showInfoAlert(
        context,
        title: 'Image trop lourde',
        message: 'Choisissez une image de moins de 15 Mo.',
      );
    }
    return null;
  }
  final photo = _compressPhoto(source);
  if (photo == null && context.mounted) {
    await _showInfoAlert(
      context,
      title: 'Image illisible',
      message: 'Ce fichier n’est pas une image reconnue (JPEG, PNG, WebP…).',
    );
  }
  return photo;
}

String? _compressPhoto(Uint8List source) {
  final decoded = img.decodeImage(source);
  if (decoded == null) return null;
  // Respecte l'orientation des photos de téléphone, puis recadre au centre.
  final oriented = img.bakeOrientation(decoded);
  final side = math.min(oriented.width, oriented.height);
  final square = img.copyCrop(
    oriented,
    x: (oriented.width - side) ~/ 2,
    y: (oriented.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final resized = img.copyResize(
    square,
    width: _photoSize,
    height: _photoSize,
    interpolation: img.Interpolation.average,
  );
  return base64Encode(img.encodeJpg(resized, quality: 82));
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first
        .substring(0, math.min(2, parts.first.length))
        .toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

// Avatar : photo de profil si elle existe, sinon initiales sur fond coloré.
class ErpUserAvatar extends StatelessWidget {
  final String name;
  final String? photo;
  final double radius;

  const ErpUserAvatar({
    super.key,
    required this.name,
    required this.photo,
    this.radius = 20,
  });

  static final _cache = <String, MemoryImage>{};

  static const _palette = [
    Color(0xFF3949AB),
    Color(0xFF00897B),
    Color(0xFF8E24AA),
    Color(0xFFF4511E),
    Color(0xFF546E7A),
    Color(0xFF43A047),
  ];

  @override
  Widget build(BuildContext context) {
    final data = photo;
    if (data != null && data.isNotEmpty) {
      final image = _cache.putIfAbsent(
        data,
        () => MemoryImage(base64Decode(data)),
      );
      return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFE8EAF6),
        backgroundImage: image,
      );
    }
    final color = _palette[name.hashCode.abs() % _palette.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        _initials(name),
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.7,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
