import 'dart:convert';
import 'dart:io';

/// Back up copied fallback packages; leave user profiles and plugins intact.
Future<List<String>> migrateHarnessLegacyModules(
  Directory home,
  String cliPath,
) async {
  var bundled = File(cliPath).parent;
  while (!bundled.path.replaceAll('\\', '/').endsWith('/node_modules')) {
    if (bundled.parent.path == bundled.path) return [];
    bundled = bundled.parent;
  }
  final modules = Directory('${home.path}/profiles/node_modules');
  // Legacy releases linked the entire fallback root into a signed App.
  // Detach the link itself, never migrate or mutate packages inside that App.
  if (await FileSystemEntity.type(modules.path, followLinks: false) ==
      FileSystemEntityType.link) {
    final backups = await Directory(
      '${home.path}/module-migration-backups',
    ).create(recursive: true);
    final backup = await backups.createTemp('linked-root-');
    final saved = '${backup.path}/node_modules';
    await Link(modules.path).rename(saved);
    await modules.create(recursive: true);
    return [saved];
  }
  if (!await modules.exists()) return [];
  final lock = await File(
    '${home.path}/.vibekits-module-migration.lock',
  ).open(mode: FileMode.append);
  await lock.lock(FileLock.blockingExclusive);
  final moved = <String>[];
  Directory? backup;
  try {
    Future<void> inspect(String name) async {
      final path = '${modules.path}/$name';
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.directory) {
        return;
      }
      final manifest = File('$path/package.json');
      if (!await manifest.exists()) return;
      Object? value;
      try {
        value = jsonDecode(await manifest.readAsString());
      } on FormatException {
        return;
      }
      if (value is! Map || value['name'] != name) return;
      final dsh = value['dsh'];
      if (dsh is Map &&
          dsh['moduleFallback'] is Map &&
          (dsh['moduleFallback'] as Map)['targets'] != null) {
        return;
      }
      // Profiles may live on an external volume through a directory link.
      // Keep backups beside the real modules directory for atomic rename.
      final realModules = Directory(await modules.resolveSymbolicLinks());
      backup ??= await Directory(
        '${realModules.parent.path}/.vibekits-module-backups',
      ).create(recursive: true).then((d) => d.createTemp('legacy-'));
      final destination = Directory('${backup!.path}/$name');
      await destination.parent.create(recursive: true);
      await Directory(path).rename(destination.path);
      moved.add(destination.path);
    }

    await for (final entry in bundled.list(followLinks: false)) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (name.startsWith('@') && entry is Directory) {
        await for (final child in entry.list(followLinks: false)) {
          final leaf = child.uri.pathSegments.where((s) => s.isNotEmpty).last;
          await inspect('$name/$leaf');
        }
      } else if (!name.startsWith('.')) {
        await inspect(name);
      }
    }
    return moved;
  } finally {
    await lock.unlock();
    await lock.close();
  }
}

String harnessStartupDiagnostic(String output) {
  final lines = output
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty);
  for (final line in lines) {
    if (line.contains('Error:') ||
        line.contains('ENOSPC') ||
        line.contains('fatal load failure')) {
      return line;
    }
  }
  return lines.isEmpty ? '' : lines.last;
}

Uri? harnessAnnouncedUrl(String line, Uri expected) {
  final match = RegExp(r'dsh web: (http://[^\s]+)').firstMatch(line);
  final candidate = match == null ? null : Uri.tryParse(match.group(1)!);
  if (candidate == null ||
      candidate.scheme != expected.scheme ||
      candidate.host != expected.host ||
      candidate.port != expected.port ||
      candidate.userInfo.isNotEmpty ||
      candidate.path != '/') {
    return null;
  }
  return candidate;
}
