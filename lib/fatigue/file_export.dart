import 'file_export_io.dart'
    if (dart.library.js_interop) 'file_export_web.dart'
    as platform;

/// Hands a JSON file to the user: a download in the browser, the share
/// sheet on phones and desktop (save to Files, AirDrop, email, Drive…).
Future<void> exportJsonFile(String fileName, String json) =>
    platform.exportJsonFile(fileName, json);
