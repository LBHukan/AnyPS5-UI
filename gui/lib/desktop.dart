import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

class Desktop {
  static const channel = MethodChannel('anyps5/desktop');

  static Future<String?> pick(
    String kind, {
    String title = 'Selecionar arquivo',
  }) => channel.invokeMethod<String>('pick', {'kind': kind, 'title': title});

  static Directory findRoot() {
    for (final origin in [
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ]) {
      var candidate = origin;
      for (var depth = 0; depth < 10; depth++) {
        if (File('${candidate.path}/core/relinker/main.cpp').existsSync() ||
            File('${candidate.path}/downloads/relinker.exe').existsSync())
          return candidate;
        if (candidate.parent.path == candidate.path) break;
        candidate = candidate.parent;
      }
    }
    return Directory.current;
  }

  static File get settings {
    final folder =
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return File('$folder/AnyPS5Gui/last-profile.json');
  }

  static Future<void> saveJson(File file, Map<String, dynamic> value) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
  }

  static Future<void> openFolder(String path) async {
    if (!await Directory(path).exists())
      throw const FormatException('A pasta ainda não existe.');
    await channel.invokeMethod<void>('openFolder', File(path).absolute.path);
  }
}

class ProcessSession {
  Process? process;
  bool cancelled = false;
  final void Function(String) log;
  ProcessSession(this.log);

  Future<int> run(
    String executable,
    List<String> args, {
    required String cwd,
    Map<String, String>? environment,
    bool enter = false,
  }) async {
    cancelled = false;
    final child = await Process.start(
      executable,
      args,
      workingDirectory: cwd,
      environment: environment,
      runInShell: false,
    );
    process = child;
    Future<void> pump(Stream<List<int>> stream) async {
      await for (final text in stream.transform(
        const Utf8Decoder(allowMalformed: true),
      ))
        log(text);
    }

    if (enter) child.stdin.writeln();
    try {
      final output = [pump(child.stdout), pump(child.stderr)];
      final code = await child.exitCode;
      await Future.wait(output);
      return code;
    } finally {
      await child.stdin.close();
      process = null;
    }
  }

  Future<void> stop() async {
    final child = process;
    if (child == null) return;
    cancelled = true;
    if (Platform.isWindows) {
      await Process.run('taskkill.exe', [
        '/PID',
        '${child.pid}',
        '/T',
        '/F',
      ], runInShell: false);
    } else {
      child.kill();
    }
  }
}
