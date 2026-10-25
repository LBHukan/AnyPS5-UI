import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'desktop.dart';
import 'parameters.dart';

const accent = Color(0xff68e2c2);
const background = Color(0xff10141c);
const panel = Color(0xff191f2b);
const muted = Color(0xff9aa8bc);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AnyPS5App());
}

class AnyPS5App extends StatelessWidget {
  const AnyPS5App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AnyPS5 Studio',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: panel,
        primary: accent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: background.withValues(alpha: .65),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: Color(0xff30394a)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: Color(0xff30394a)),
        ),
        labelStyle: const TextStyle(color: muted, fontSize: 13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 19),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    ),
    home: const Workbench(),
  );
}

class Workbench extends StatefulWidget {
  const Workbench({super.key});
  @override
  State<Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<Workbench> {
  Parameters p = Parameters();
  late final Directory root;
  late final ProcessSession session;
  final controllers = <String, TextEditingController>{};
  final logController = TextEditingController();
  final logScroll = ScrollController();
  int page = 0;
  int revision = 0;
  bool busy = false;
  bool ready = false;
  String status = 'Carregando configurações';
  String? help;
  Timer? logTimer;
  String pendingLog = '';

  @override
  void initState() {
    super.initState();
    root = Desktop.findRoot();
    Directory.current = root;
    session = ProcessSession(appendLog);
    initialize();
  }

  Future<void> initialize() async {
    try {
      if (await Desktop.settings.exists()) {
        p = Parameters.fromJson(
          jsonDecode(await Desktop.settings.readAsString()),
        );
      }
    } catch (e) {
      appendLog('Não foi possível restaurar o último perfil: $e\n');
    }
    if (!File(p.relinker).existsSync())
      p.relinker = '${root.path}/downloads/relinker.exe';
    if (mounted)
      setState(() {
        ready = true;
        status = 'Pronto para configurar';
      });
    appendLog(
      'AnyPS5 Studio • projeto: ${root.path}\nSelecione um ELF para começar. F10: overlay • F12: captura no jogo.\n',
    );
    await inspectRelinker();
  }

  void appendLog(String text) {
    pendingLog += text;
    logTimer ??= Timer(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      var content = logController.text + pendingLog;
      pendingLog = '';
      if (content.length > 150000)
        content =
            '[Log anterior truncado]\n${content.substring(content.length - 120000)}';
      logController.text = content;
      logTimer = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (logScroll.hasClients)
          logScroll.jumpTo(logScroll.position.maxScrollExtent);
      });
    });
  }

  Future<void> inspectRelinker({bool printHelp = false}) async {
    final path = p.relinker;
    try {
      final result = await Process.run(path, [
        '--help',
      ], runInShell: false).timeout(const Duration(seconds: 15));
      if (result.exitCode != 0)
        throw FormatException('Código ${result.exitCode}: ${result.stderr}');
      if (mounted && path == p.relinker)
        setState(() {
          help = '${result.stdout}';
        });
      if (printHelp) appendLog('${result.stdout}\n');
    } catch (e) {
      if (mounted && path == p.relinker)
        setState(() {
          help = null;
        });
      appendLog('Relinker indisponível: $e\n');
    }
  }

  void update(VoidCallback change) => setState(change);

  void notify(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> guarded(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      notify('$e');
      appendLog('Erro: $e\n');
    }
  }

  TextEditingController controller(String id, String value) => controllers
      .putIfAbsent('$revision:$id', () => TextEditingController(text: value));

  Widget field(
    String id,
    String label,
    String value,
    ValueChanged<String> changed, {
    String? kind,
    String? hint,
    int maxLines = 1,
  }) {
    final c = controller(id, value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 17),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        enabled: !busy,
        style: const TextStyle(fontSize: 13.5),
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          helperMaxLines: 3,
          suffixIcon: kind == null
              ? null
              : IconButton(
                  tooltip: 'Selecionar',
                  icon: const Icon(Icons.folder_open_outlined, size: 20),
                  onPressed: busy
                      ? null
                      : () => guarded(() async {
                          final selected = await Desktop.pick(
                            kind,
                            title: label,
                          );
                          if (selected == null || !mounted) return;
                          c.text = selected;
                          update(() => changed(selected));
                          if (id == 'relinker') await inspectRelinker();
                        }),
                ),
        ),
        onChanged: (v) {
          update(() => changed(v));
          if (id == 'relinker') help = null;
        },
      ),
    );
  }

  Widget select(
    String label,
    String value,
    List<String> choices,
    ValueChanged<String> change,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 17),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$revision:$label:$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: choices
          .map(
            (v) => DropdownMenuItem(
              value: v,
              child: Text(
                v.isEmpty ? 'Padrão do projeto' : v,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          )
          .toList(),
      onChanged: busy
          ? null
          : (v) {
              if (v != null) update(() => change(v));
            },
    ),
  );

  Widget section(String title, String subtitle, List<Widget> children) =>
      Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(23),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xff293242)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: const TextStyle(color: muted, fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 23),
            ...children,
          ],
        ),
      );

  Widget toggle(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> change, {
    bool available = true,
  }) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(title, style: const TextStyle(fontSize: 13)),
    subtitle: Text(
      subtitle,
      style: const TextStyle(fontSize: 11, color: muted),
    ),
    value: value,
    onChanged: busy || !available ? null : (v) => update(() => change(v)),
  );

  List<Widget> conversion() => [
    section(
      'Arquivos da conversão',
      'Selecione o executável PS5 em formato ELF e o destino do arquivo convertido.',
      [
        field(
          'input',
          'Executável de entrada',
          p.input,
          (v) => p.input = v,
          kind: 'open',
          hint: 'ELF limpo; containers SELF precisam ser desembrulhados antes.',
        ),
        select('Operação', p.mode, [
          'Converter',
          'Verificar patches',
        ], (v) => p.mode = v),
        if (p.mode == 'Converter') ...[
          Row(
            children: [
              Expanded(
                child: select('Sistema de saída', p.target, [
                  'Windows',
                  'Linux',
                  'macOS',
                ], (v) => p.target = v),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: select(
                  'Filtro de imports não usados',
                  '${p.unusedFilter}',
                  ['0', '1', '2'],
                  (v) => p.unusedFilter = int.parse(v),
                ),
              ),
            ],
          ),
          field(
            'output',
            'Executável de saída',
            p.output,
            (v) => p.output = v,
            kind: 'save',
            hint: 'Windows: .exe • Linux: .elf • macOS: Mach-O',
          ),
          toggle(
            'Executar após converter',
            '--autorun • requer app0/ e bibliotecas preparadas',
            p.autorun,
            (v) => p.autorun = v,
          ),
        ] else ...[
          field(
            'verifyPatches',
            'Arquivo de patches a verificar',
            p.verifyPatches,
            (v) => p.verifyPatches = v,
            kind: 'open',
          ),
          toggle(
            'Validar sobre uma saída Linux convertida',
            '--verify-output • nenhuma saída será escrita',
            p.verifyOutput,
            (v) => p.verifyOutput = v,
          ),
        ],
      ],
    ),
    section(
      'Compatibilidade e diagnóstico',
      'As opções são enviadas diretamente ao relinker. Padrões do projeto são preservados.',
      [
        for (final key in switchOptions.keys.take(8))
          toggle(
            switchOptions[key]!,
            help != null && !help!.contains(key)
                ? '$key • indisponível neste relinker'
                : key,
            p.flags[key] == true,
            (v) => p.flags[key] = v,
            available:
                p.mode == 'Converter' && (help == null || help!.contains(key)),
          ),
      ],
    ),
    section(
      'Bibliotecas para Windows',
      'O runtime oficial está em downloads/runtime-windows/libs. Os recursos do título devem ficar em app0/ ao lado da saída.',
      [
        OutlinedButton.icon(
          onPressed: busy ? null : () => guarded(installLibraries),
          icon: const Icon(Icons.library_add_outlined, size: 18),
          label: const Text('Copiar bibliotecas para a saída'),
        ),
        const SizedBox(height: 12),
        const Text(
          'A cópia preserva arquivos existentes. Jogos dependem das limitações de compatibilidade do AnyPS5.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    ),
  ];

  List<Widget> runtime() => [
    section(
      'Vídeo e idioma',
      'Estas variáveis são aplicadas somente ao processo iniciado pela interface.',
      [
        select(
          'Modo de apresentação',
          p.environment['ANYPS5_PRESENT_MODE'] ?? '',
          ['', 'fifo', 'fifo_latest_ready', 'mailbox', 'immediate'],
          (v) => p.environment['ANYPS5_PRESENT_MODE'] = v,
        ),
        select(
          'Idioma do jogo',
          p.environment['ANYPS5_LANGUAGE'] ?? '',
          ['', '1', '7', '17', '18', '3', '20', '0', '2', '4', '5'],
          (v) => p.environment['ANYPS5_LANGUAGE'] = v,
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 20),
          child: Text(
            'Vazio = padrão • 17 Português (Brasil) • 7 Português (Portugal)\n1 Inglês (EUA) • 18 Inglês (Reino Unido) • 3/20 Espanhol • 0 Japonês • 2 Francês • 4 Alemão • 5 Italiano',
            style: TextStyle(fontSize: 11, color: muted, height: 1.7),
          ),
        ),
        for (final key in runtimeFields.keys.take(4))
          field(
            key,
            runtimeFields[key]!,
            p.environment[key] ?? '',
            (v) => p.environment[key] = v,
            kind: key == 'ANYPS5_GPU' ? null : 'folder',
            hint: key,
          ),
        toggle(
          'Exibir overlay de desempenho',
          'ANYPS5_OVERLAY=1 • também pode ser alternado com F10',
          p.environment['ANYPS5_OVERLAY'] == '1',
          (v) => p.environment['ANYPS5_OVERLAY'] = v ? '1' : '',
        ),
        select(
          'Posição do overlay',
          p.environment['ANYPS5_OVERLAY_POS'] ?? '',
          ['', 'tl', 'tr', 'bl', 'br'],
          (v) => p.environment['ANYPS5_OVERLAY_POS'] = v,
        ),
      ],
    ),
    section(
      'Cache e rastreamento',
      'Campos vazios usam a configuração padrão do runtime.',
      [
        toggle(
          'Desativar cache de shaders',
          'ANYPS5_NO_SHADER_CACHE=1',
          p.environment['ANYPS5_NO_SHADER_CACHE'] == '1',
          (v) => p.environment['ANYPS5_NO_SHADER_CACHE'] = v ? '1' : '',
        ),
        for (final key in runtimeFields.keys.skip(4))
          field(
            key,
            runtimeFields[key]!,
            p.environment[key] ?? '',
            (v) => p.environment[key] = v,
            hint: key,
          ),
        field(
          'extraEnvironment',
          'Outras variáveis de ambiente',
          p.extraEnvironment,
          (v) => p.extraEnvironment = v,
          maxLines: 5,
          hint:
              'Uma por linha: NOME=valor. Consulte docs/user/USAGE.md para outros parâmetros.',
        ),
      ],
    ),
  ];

  List<Widget> advanced() => [
    section(
      'Módulos e patches',
      'Caminhos relativos são resolvidos a partir de ${root.path}.',
      [
        for (final key in valueOptions.keys.take(3))
          field(
            key,
            valueOptions[key]!,
            p.values[key] ?? '',
            (v) => p.values[key] = v,
            kind: key == '--rpath'
                ? null
                : key == '--patches'
                ? 'open'
                : 'folder',
            hint: key == '--sce-module-path'
                ? '$key • pasta pai de sce_module/, sce_modules/ ou prx/'
                : key,
          ),
        for (final key in listOptions.keys)
          field(
            key,
            listOptions[key]!,
            p.lists[key] ?? '',
            (v) => p.lists[key] = v,
            maxLines: 3,
            hint:
                '$key • um valor por linha; sem aspas. Diretórios e executáveis são relativos à pasta pai dos módulos.',
          ),
      ],
    ),
    section(
      'Endereço de carregamento',
      'Preencha apenas se o título exigir uma base fixa. Aceita decimal ou hexadecimal e exige alinhamento a 64 KiB.',
      [
        for (final key in valueOptions.keys.skip(3))
          field(
            key,
            valueOptions[key]!,
            p.values[key] ?? '',
            (v) => p.values[key] = v,
            hint: key,
          ),
      ],
    ),
    section(
      'Depuração',
      'Opções obsoletas e de diagnóstico podem produzir executáveis instáveis.',
      [
        for (final key in switchOptions.keys.skip(8))
          toggle(
            switchOptions[key]!,
            key,
            p.flags[key] == true,
            (v) => p.flags[key] = v,
          ),
      ],
    ),
  ];

  Future<void> saveProfile() async {
    final path = await Desktop.pick('save', title: 'Salvar perfil JSON');
    if (path == null) return;
    await Desktop.saveJson(File(path), p.toJson());
    notify('Perfil salvo.');
  }

  Future<void> loadProfile() async {
    final path = await Desktop.pick('open', title: 'Abrir perfil JSON');
    if (path == null) return;
    final next = Parameters.fromJson(
      jsonDecode(await File(path).readAsString()),
    );
    if (!mounted) return;
    for (final c in controllers.values) c.dispose();
    controllers.clear();
    update(() {
      p = next;
      revision++;
      help = null;
    });
    await inspectRelinker();
    notify('Perfil carregado.');
  }

  Future<void> installLibraries() async {
    if (p.target != 'Windows')
      throw const FormatException('As bibliotecas baixadas são para Windows.');
    if (p.output.trim().isEmpty)
      throw const FormatException('Selecione primeiro o arquivo de saída.');
    final source = Directory('${root.path}/downloads/runtime-windows/libs');
    if (!await source.exists())
      throw const FormatException(
        'Runtime não encontrado em downloads/runtime-windows/libs.',
      );
    final destination = Directory(
      '${File(p.output).absolute.parent.path}/libs',
    );
    if (source.absolute.path.toLowerCase() ==
        destination.absolute.path.toLowerCase())
      throw const FormatException('As bibliotecas já estão nesse diretório.');
    update(() {
      busy = true;
      status = 'Copiando bibliotecas';
    });
    var count = 0;
    try {
      await for (final entity in source.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final relative = entity.path.substring(source.path.length + 1);
        final out = File('${destination.path}/$relative');
        if (await out.exists()) continue;
        await out.parent.create(recursive: true);
        await entity.copy(out.path);
        count++;
      }
      appendLog(
        '$count bibliotecas/arquivos copiados para ${destination.path}. Arquivos existentes preservados.\n',
      );
      notify('Bibliotecas preparadas. Coloque os recursos do título em app0/.');
    } finally {
      if (mounted)
        update(() {
          busy = false;
          status = 'Bibliotecas preparadas';
        });
    }
  }

  Future<void> execute({bool game = false}) async {
    update(() {
      busy = true;
      status = 'Validando parâmetros';
    });
    try {
      var executable = p.relinker;
      var args = <String>[];
      var cwd = root.path;
      if (game) {
        if (p.target != 'Windows' || !File(p.output).existsSync())
          throw const FormatException(
            'Selecione uma saída Windows existente para executar.',
          );
        executable = File(p.output).absolute.path;
        cwd = File(executable).parent.path;
      } else {
        await inspectRelinker();
        if (help == null)
          throw const FormatException(
            'O relinker não respondeu ao comando --help.',
          );
        p.validate(help: help);
        args = p.arguments();
        if (p.mode == 'Converter') {
          if (await File(p.output).exists()) {
            final replace = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Substituir saída existente?'),
                content: Text(File(p.output).absolute.path),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Substituir'),
                  ),
                ],
              ),
            );
            if (replace != true) return;
          }
          await File(p.output).parent.create(recursive: true);
        }
      }
      final environment = p.runtimeEnvironment();
      await Desktop.saveJson(Desktop.settings, p.toJson());
      update(
        () => status = game
            ? 'Executando título'
            : p.mode == 'Converter'
            ? 'Convertendo executável'
            : 'Verificando patches',
      );
      appendLog('\n> ${displayCommand(executable, args)}\nDiretório: $cwd\n');
      final code = await session.run(
        executable,
        args,
        cwd: cwd,
        environment: environment,
        enter: !game && p.autorun && p.mode == 'Converter',
      );
      final message = session.cancelled
          ? 'Processo interrompido'
          : code == 0
          ? 'Concluído com sucesso'
          : 'Falhou • código $code';
      appendLog('\n$message\n');
      if (mounted) {
        update(() => status = message);
        notify(message);
      }
    } catch (e) {
      appendLog('Erro: $e\n');
      if (mounted) {
        update(() => status = 'Verifique os parâmetros');
        notify('$e');
      }
    } finally {
      if (mounted)
        update(() {
          busy = false;
          if (status == 'Validando parâmetros') status = 'Operação cancelada';
        });
    }
  }

  Widget summary() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      section('Sua configuração', 'PARÂMETROS ATIVOS', [
        Row(
          children: [
            const Icon(Icons.computer_rounded, color: accent, size: 30),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.target,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  p.mode,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Divider(),
        ),
        Text(
          '${p.flags.values.where((v) => v).length} opções ativadas',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy || !ready ? null : () => execute(),
          icon: Icon(
            p.mode == 'Converter' ? Icons.bolt : Icons.fact_check_outlined,
            size: 20,
          ),
          label: Text(
            p.mode == 'Converter'
                ? 'Converter executável'
                : 'Verificar patches',
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: busy ? null : () => execute(game: true),
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          label: const Text('Executar saída'),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: busy ? () => guarded(session.stop) : null,
          icon: const Icon(Icons.stop_rounded, size: 19),
          label: const Text('Interromper processo'),
        ),
      ]),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: .18)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: accent, size: 20),
            SizedBox(height: 10),
            Text(
              'Antes de executar',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Prepare libs/ com as bibliotecas AnyPS5 e app0/ com os recursos originais do título. A compatibilidade varia por jogo.',
              style: TextStyle(fontSize: 12, color: muted, height: 1.6),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      TextButton.icon(
        onPressed: () => guarded(() => Desktop.openFolder(root.path)),
        icon: const Icon(Icons.folder_outlined, size: 17),
        label: const Text('Abrir pasta do projeto'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (!ready)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final titles = ['Conversão', 'Execução', 'Avançado'];
    final subtitles = [
      'Transforme executáveis PS5 para o seu computador.',
      'Ajuste o ambiente usado ao iniciar o título.',
      'Configure módulos, patches e opções de diagnóstico.',
    ];
    final command = displayCommand(
      p.relinker.isEmpty ? 'relinker.exe' : p.relinker,
      p.arguments(),
    );
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 192,
            color: const Color(0xff141a24),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Icon(
                    Icons.sports_esports_rounded,
                    color: accent,
                    size: 33,
                  ),
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Text(
                    'AnyPS5',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.8,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 13),
                  child: Text(
                    'S T U D I O',
                    style: TextStyle(color: muted, fontSize: 10),
                  ),
                ),
                const SizedBox(height: 40),
                for (var i = 0; i < titles.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      selected: page == i,
                      selectedTileColor: accent.withValues(alpha: .1),
                      selectedColor: accent,
                      leading: Icon(
                        [
                          Icons.swap_horiz_rounded,
                          Icons.tune_rounded,
                          Icons.code_rounded,
                        ][i],
                        size: 21,
                      ),
                      title: Text(
                        titles[i],
                        style: const TextStyle(fontSize: 13),
                      ),
                      onTap: () => update(() => page = i),
                    ),
                  ),
                const Spacer(),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'FLUTTER DESKTOP\nWindows • interface local',
                    style: TextStyle(fontSize: 10, height: 1.8, color: muted),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(30, 23, 30, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titles[page],
                              style: const TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitles[page],
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy ? null : () => guarded(loadProfile),
                        icon: const Icon(Icons.file_open_outlined, size: 17),
                        label: const Text('Abrir perfil'),
                      ),
                      const SizedBox(width: 9),
                      OutlinedButton.icon(
                        onPressed: busy ? null : () => guarded(saveProfile),
                        icon: const Icon(Icons.save_outlined, size: 17),
                        label: const Text('Salvar perfil'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Row(
                    children: [
                      Expanded(
                        child: field(
                          'relinker',
                          'Relinker executável',
                          p.relinker,
                          (v) => p.relinker = v,
                          kind: 'open',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 17),
                        child: IconButton(
                          tooltip: 'Exibir ajuda do relinker',
                          onPressed: busy
                              ? null
                              : () => guarded(
                                  () => inspectRelinker(printHelp: true),
                                ),
                          icon: const Icon(Icons.help_outline, color: muted),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(30, 0, 30, 10),
                      child: constraints.maxWidth > 820
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    children: page == 0
                                        ? conversion()
                                        : page == 1
                                        ? runtime()
                                        : advanced(),
                                  ),
                                ),
                                const SizedBox(width: 22),
                                SizedBox(width: 270, child: summary()),
                              ],
                            )
                          : Column(
                              children: [
                                ...(page == 0
                                    ? conversion()
                                    : page == 1
                                    ? runtime()
                                    : advanced()),
                                summary(),
                              ],
                            ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                  decoration: const BoxDecoration(
                    color: Color(0xff121821),
                    border: Border(top: BorderSide(color: Color(0xff293242))),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.terminal_rounded,
                            size: 16,
                            color: accent,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'COMANDO',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.6,
                              color: muted,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: command),
                              );
                              notify(
                                'Comando copiado. Execução usa argumentos diretos, sem shell.',
                              );
                            },
                            icon: const Icon(Icons.copy_outlined, size: 14),
                            label: const Text(
                              'Copiar',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: 38,
                        child: SingleChildScrollView(
                          child: SelectableText(
                            command,
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 11,
                              color: Color(0xffc5d5e6),
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: busy ? Colors.amber : accent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            status,
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => guarded(() async {
                              final file = await Desktop.pick(
                                'save',
                                title: 'Salvar log',
                              );
                              if (file != null)
                                await File(file).writeAsString(
                                  logController.text + pendingLog,
                                );
                            }),
                            child: const Text(
                              'Salvar log',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: 100,
                        child: TextField(
                          controller: logController,
                          scrollController: logScroll,
                          readOnly: true,
                          maxLines: null,
                          expands: true,
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 11,
                            color: muted,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (busy) const LinearProgressIndicator(minHeight: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    logTimer?.cancel();
    for (final c in controllers.values) c.dispose();
    logController.dispose();
    logScroll.dispose();
    super.dispose();
  }
}
