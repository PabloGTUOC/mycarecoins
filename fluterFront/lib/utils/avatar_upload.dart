import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';

/// The image types the avatar endpoints accept, as ALLOWED_MIME_TYPES in
/// routes/me.js and routes/families.js. Keep the two in step.
const _jpeg = 'image/jpeg';
const _png = 'image/png';
const _webp = 'image/webp';

/// What the bytes actually are, by magic number.
///
/// The name the picker hands back is not evidence — iOS reports `.jpg` for a
/// re-encoded HEIC and the extension can disagree with the payload either way
/// — and the server type-checks the part it receives, so the header has to be
/// true. Returns null for anything the server would refuse.
String? sniffImageMime(List<int> b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return _jpeg;
  }
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47 &&
      b[4] == 0x0D &&
      b[5] == 0x0A &&
      b[6] == 0x1A &&
      b[7] == 0x0A) {
    return _png;
  }
  // RIFF....WEBP
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return _webp;
  }
  return null;
}

/// Opens the gallery picker and uploads the chosen image as multipart
/// `avatar` to [path] (e.g. `/api/me/avatar`). Returns true on success.
Future<bool> pickAndUploadAvatar(BuildContext context, String path,
    {String successMessage = 'Avatar updated successfully!'}) async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 800,
    maxHeight: 800,
    imageQuality: 85,
  );
  if (picked == null || !context.mounted) return false;
  final bytes = await picked.readAsBytes();
  if (!context.mounted) return false;
  final app = context.read<AppState>();

  final mime = sniffImageMime(bytes);
  if (mime == null) {
    // Better a plain refusal here than the server's, which arrives as a bare
    // "Only JPEG, PNG, and WebP images are allowed." after a 2 MB round trip.
    app.setError(AppLocalizations.of(context).errAvatarType);
    return false;
  }

  return app.runAction(() async {
    await app.api.uploadFile(path,
        field: 'avatar',
        bytes: bytes,
        filename: picked.name,
        contentType: mime);
  }, successMessage);
}
