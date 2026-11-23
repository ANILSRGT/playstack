import 'dart:io';

import 'playstack_show_rules.dart';

/// A store in a file.
PlayStackShowStore fileStore(String path) => _FileStore(File(path));

class _FileStore extends PlayStackShowStore {
  _FileStore(this.file);

  final File file;

  @override
  Future<String?> read() async =>
      await file.exists() ? await file.readAsString() : null;

  @override
  Future<void> write(String data) async {
    await file.parent.create(recursive: true);
    // Written next to it and renamed, so a crash never leaves half a file.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(data, flush: true);
    await temp.rename(file.path);
  }
}
