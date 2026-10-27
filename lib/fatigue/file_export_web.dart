import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Downloads straight away. The Web Share sheet is skipped on purpose:
/// on a laptop a file in Downloads is what you want for training.
Future<void> exportJsonFile(String fileName, String json) async {
  final blob = web.Blob(
    [json.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
