import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> exportJsonFile(String fileName, String json) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(utf8.encode(json)),
          mimeType: 'application/json',
          name: fileName,
        ),
      ],
      fileNameOverrides: [fileName],
      subject: fileName,
    ),
  );
}
