import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:anyps5_gui/parameters.dart';
import 'package:anyps5_gui/desktop.dart';

void main() {
  late Directory temp;
  late Parameters p;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('anyps5 gui ');
    p = Parameters()
      ..relinker = Platform.resolvedExecutable
      ..input = '${temp.path}/entrada com espaços.elf'
      ..output = '${temp.path}/saída.exe';
    File(p.input).writeAsBytesSync([0x7f, 69, 76, 70]);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('Caminhos, ORIGIN e opções repetidas preservam argumentos', () {
    p.lists['--module-dir'] = 'Media/Plugins\nPasta com espaços\n';
    p.lists['--executable'] = 'picker/picker.bin';
    p.validate();
    final args = p.arguments();
    expect(args[args.indexOf('--rpath') + 1], r'$ORIGIN/libs');
    expect(args.where((v) => v == '--module-dir').length, 2);
    expect(args[args.length - 2], p.input);
    expect(args.last, p.output);
  });

  test('Verificação remove opções de conversão e caminho de saída', () {
    p.mode = 'Verificar patches';
    p.verifyPatches = '${temp.path}/patch.toml';
    p.flags['--windows-gui'] = true;
    p.flags['--registry'] = true;
    p.autorun = true;
    File(p.verifyPatches).writeAsStringSync('format = 1');
    p.validate();
    expect(p.arguments(), ['--verify-patches', p.verifyPatches, p.input]);
    p.verifyOutput = true;
    p.values['--sce-module-path'] = temp.path;
    expect(p.arguments(), [
      '--verify-patches',
      p.verifyPatches,
      '--verify-output',
      p.input,
    ]);
  });

  test('Conflitos e versões incompatíveis impedem execução', () {
    p.flags['--trace-imports'] = true;
    p.flags['--lazy-binding'] = true;
    expect(() => p.validate(), throwsFormatException);
    p.flags.clear();
    p.target = 'Linux';
    p.flags['--windows-gui'] = true;
    expect(() => p.validate(), throwsFormatException);
    p.flags.clear();
    p.target = 'Windows';
    p.values['--windows-fixed-base'] = '0x20001';
    expect(() => p.validate(), throwsFormatException);
    p.values.remove('--windows-fixed-base');
    p.flags['--frame-red-zone'] = true;
    expect(() => p.validate(help: '--windows --rpath'), throwsFormatException);
  });

  test('Entrada não pode ser substituída pelo arquivo de saída', () {
    p.output = p.input;
    expect(() => p.validate(), throwsFormatException);
  });

  test('Perfis e variáveis preservam valores sem executar shell', () {
    p.environment['ANYPS5_LANGUAGE'] = '17';
    p.extraEnvironment = 'APS5_TRACE_CALLS=all\nCUSTOM=a=b & echo teste';
    final restored = Parameters.fromJson(p.toJson());
    expect(restored.runtimeEnvironment()['CUSTOM'], 'a=b & echo teste');
    expect(restored.runtimeEnvironment()['ANYPS5_LANGUAGE'], '17');
    expect(restored.arguments(), p.arguments());
    p.extraEnvironment = 'não é uma variável';
    expect(p.runtimeEnvironment, throwsFormatException);
  });

  test(
    'Processo transmite stdout, stderr e código de saída reais',
    () async {
      final output = StringBuffer();
      final session = ProcessSession(output.write);
      final relinker = File('../downloads/relinker.exe').absolute.path;
      final success = await session.run(relinker, ['--help'], cwd: temp.path);
      expect(success, 0);
      expect(output.toString(), contains('Usage: relinker'));
      output.clear();
      final code = await session.run(relinker, [
        '--windows',
        '--skip-sce-module',
        p.input,
        p.output,
      ], cwd: temp.path);
      expect(code, 2);
      expect(output.toString(), contains('ELF'));
      expect(File(p.output).existsSync(), false);
      expect(session.process, isNull);
    },
    skip:
        !Platform.isWindows || !File('../downloads/relinker.exe').existsSync(),
  );
}
