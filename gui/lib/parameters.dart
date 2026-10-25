import 'dart:io';

const switchOptions = <String, String>{
  '--windows-diagnostics': 'Diagnóstico de dependências na inicialização',
  '--windows-gui': 'Executável sem janela de console',
  '--to-intel': 'Adaptar instruções AMD para Intel',
  '--to-rosetta': 'Adaptar instruções para Rosetta',
  '--registry': 'Gerar registros JSON de importações',
  '--trace-imports': 'Instrumentar chamadas das bibliotecas',
  '--frame-red-zone': 'Criar frames para funções com red zone',
  '--no-patches': 'Desativar patches automáticos',
  '--trap-sdk-syscall-stubs': 'Interceptar stubs de syscall do SDK (depuração)',
  '--skip-syscall-check': 'Ignorar verificação de syscalls (obsoleto)',
  '--skip-sce-module': 'Ignorar módulos do título (obsoleto)',
  '--lazy-binding': 'Resolver símbolos sob demanda (obsoleto)',
};

const valueOptions = <String, String>{
  '--sce-module-path': 'Pasta pai dos módulos',
  '--rpath': 'Caminho das bibliotecas de sistema',
  '--patches': 'Arquivo de patches TOML',
  '--windows-fixed-base': 'Endereço fixo no Windows',
  '--linux-fixed-base': 'Endereço fixo no Linux',
  '--macos-fixed-base': 'Endereço fixo no macOS',
};

const listOptions = <String, String>{
  '--module-dir': 'Diretórios extras de módulos',
  '--executable': 'Executáveis adicionais do título',
  '--exclude-sce-module': 'Módulos excluídos por nome (obsoleto)',
};

const runtimeFields = <String, String>{
  'ANYPS5_GPU': 'GPU (parte do nome; vazio = automática)',
  'ANYPS5_SHADER_CACHE_DIR': 'Diretório do cache de shaders',
  'ANYPS5_SCREENSHOTS': 'Diretório de capturas de tela',
  'ANYPS5_SYSTEM_FONTS': 'Diretório de fontes do sistema',
  'APS5_TRACE_CALLS': 'Bibliotecas rastreadas (all ou separadas por vírgula)',
  'APS5_TEXTURE_CACHE_MIB': 'Orçamento do cache de texturas (MiB)',
  'APS5_PIPELINE_JOURNAL_THREADS': 'Threads de compilação antecipada',
};

class Parameters {
  String relinker = '';
  String input = '';
  String output = '';
  String target = 'Windows';
  String mode = 'Converter';
  String verifyPatches = '';
  bool verifyOutput = false;
  bool autorun = false;
  int unusedFilter = 0;
  final flags = <String, bool>{};
  final values = <String, String>{'--rpath': r'$ORIGIN/libs'};
  final lists = <String, String>{};
  final environment = <String, String>{};
  String extraEnvironment = '';

  List<String> arguments() {
    final args = <String>[];
    if (mode == 'Verificar patches') {
      args.addAll(['--verify-patches', verifyPatches]);
      if (verifyOutput) args.add('--verify-output');
    } else {
      if (target == 'Windows') args.add('--windows');
      if (target == 'macOS') args.add('--macos');
      for (final option in switchOptions.keys) {
        if (flags[option] == true && option != '--skip-sce-module')
          args.add(option);
      }
      args.add('unused-filter=$unusedFilter');
      for (final option in valueOptions.keys.where(
        (v) => v != '--sce-module-path',
      )) {
        final value = values[option]?.trim() ?? '';
        if (value.isNotEmpty) args.addAll([option, value]);
      }
      if (autorun) args.add('--autorun');
    }
    if (!(mode == 'Verificar patches' && verifyOutput)) {
      if (flags['--skip-sce-module'] == true) args.add('--skip-sce-module');
      final parent = values['--sce-module-path']?.trim() ?? '';
      if (parent.isNotEmpty) args.addAll(['--sce-module-path', parent]);
      for (final option in listOptions.keys) {
        for (final value in lines(lists[option] ?? ''))
          args.addAll([option, value]);
      }
    }
    args.add(input.trim());
    if (mode == 'Converter') args.add(output.trim());
    return args;
  }

  Map<String, String> runtimeEnvironment() {
    final result = <String, String>{};
    for (final entry in environment.entries) {
      if (entry.value.isNotEmpty) result[entry.key] = entry.value;
    }
    for (final line in lines(extraEnvironment)) {
      final index = line.indexOf('=');
      if (index < 1 ||
          !RegExp(
            r'^[A-Za-z_][A-Za-z0-9_]*$',
          ).hasMatch(line.substring(0, index))) {
        throw const FormatException('Use NOME=valor, uma variável por linha.');
      }
      result[line.substring(0, index)] = line.substring(index + 1);
    }
    return result;
  }

  void validate({String? help}) {
    void require(bool condition, String message) {
      if (!condition) throw FormatException(message);
    }

    require(
      File(relinker).existsSync(),
      'Selecione um relinker.exe existente.',
    );
    require(
      File(input).existsSync(),
      'Selecione um arquivo de entrada existente.',
    );
    final verifying = mode == 'Verificar patches';
    if (verifying) {
      require(
        File(verifyPatches).existsSync(),
        'Selecione o arquivo TOML a verificar.',
      );
    } else {
      require(output.trim().isNotEmpty, 'Selecione o arquivo de saída.');
      require(
        File(input).absolute.path.toLowerCase() !=
            File(output).absolute.path.toLowerCase(),
        'A saída deve ser diferente da entrada.',
      );
      if (File(output).existsSync())
        require(
          !FileSystemEntity.identicalSync(input, output),
          'A saída aponta para o arquivo de entrada.',
        );
      require(
        !(flags['--no-patches'] == true &&
            (values['--patches'] ?? '').isNotEmpty),
        '--no-patches conflita com o arquivo de patches.',
      );
      require(
        !(flags['--trace-imports'] == true && flags['--lazy-binding'] == true),
        'Rastreamento de imports conflita com lazy binding.',
      );
      require(
        !(flags['--to-rosetta'] == true && target == 'Windows'),
        'Rosetta não pode ser usado com Windows.',
      );
      require(
        !(flags['--trace-imports'] == true && target == 'macOS'),
        'Rastreamento de imports não suporta macOS.',
      );
      require(
        !(flags['--frame-red-zone'] == true && target != 'Windows'),
        'Frame red zone requer Windows.',
      );
      require(
        !(flags['--skip-syscall-check'] == true &&
            flags['--trap-sdk-syscall-stubs'] == true),
        'As duas opções de syscall são incompatíveis.',
      );
      for (final option in ['--windows-diagnostics', '--windows-gui']) {
        require(
          !(flags[option] == true && target != 'Windows'),
          '$option requer Windows.',
        );
      }
      for (final os in ['windows', 'linux', 'macos']) {
        final option = '--$os-fixed-base';
        final value = values[option]?.trim() ?? '';
        if (value.isEmpty) continue;
        require(
          target.toLowerCase() == os,
          '$option não corresponde ao sistema de saída.',
        );
        final address = value.startsWith(RegExp('0[xX]'))
            ? int.tryParse(value.substring(2), radix: 16)
            : int.tryParse(value);
        require(
          address != null &&
              address >= (os == 'linux' ? 0x10000 : 0x20000) &&
              address <= 0x7fffffff0000 &&
              address % 0x10000 == 0,
          '$option requer endereço alinhado a 64 KiB dentro do intervalo suportado.',
        );
        require(
          !(os == 'linux' && flags['--lazy-binding'] == true),
          'Endereço Linux fixo conflita com lazy binding.',
        );
      }
      final patches = values['--patches']?.trim() ?? '';
      require(
        patches.isEmpty || File(patches).existsSync(),
        'O arquivo de patches não existe.',
      );
      if (autorun)
        require(
          (Platform.isWindows && target == 'Windows') ||
              (Platform.isLinux && target == 'Linux') ||
              (Platform.isMacOS && target == 'macOS'),
          'A execução automática requer saída para o sistema atual.',
        );
      if (help != null) {
        for (final option in arguments().where((v) => v.startsWith('--'))) {
          require(
            help.contains(option),
            'O relinker selecionado não oferece $option. Escolha uma versão compatível.',
          );
        }
      }
    }
    if (!(verifying && verifyOutput)) {
      final parent = values['--sce-module-path']?.trim() ?? '';
      require(
        parent.isEmpty || Directory(parent).existsSync(),
        'A pasta pai dos módulos não existe.',
      );
      if (flags['--skip-sce-module'] == true) {
        require(
          parent.isEmpty && lists.values.every((v) => v.trim().isEmpty),
          'Ignorar módulos conflita com pasta pai, módulos extras e executáveis adicionais.',
        );
      }
    }
    runtimeEnvironment();
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'relinker': relinker,
    'input': input,
    'output': output,
    'target': target,
    'mode': mode,
    'verifyPatches': verifyPatches,
    'verifyOutput': verifyOutput,
    'autorun': autorun,
    'unusedFilter': unusedFilter,
    'flags': flags,
    'values': values,
    'lists': lists,
    'environment': environment,
    'extraEnvironment': extraEnvironment,
  };

  static Parameters fromJson(Map<String, dynamic> json) {
    final p = Parameters();
    p.relinker = json['relinker'] as String? ?? '';
    p.input = json['input'] as String? ?? '';
    p.output = json['output'] as String? ?? '';
    p.target = ['Windows', 'Linux', 'macOS'].contains(json['target'])
        ? json['target']
        : 'Windows';
    p.mode = json['mode'] == 'Verificar patches'
        ? 'Verificar patches'
        : 'Converter';
    p.verifyPatches = json['verifyPatches'] as String? ?? '';
    p.verifyOutput = json['verifyOutput'] == true;
    p.autorun = json['autorun'] == true;
    p.unusedFilter = [0, 1, 2].contains(json['unusedFilter'])
        ? json['unusedFilter']
        : 0;
    p.flags.addAll(Map<String, bool>.from(json['flags'] ?? {}));
    p.values.addAll(Map<String, String>.from(json['values'] ?? {}));
    p.lists.addAll(Map<String, String>.from(json['lists'] ?? {}));
    p.environment.addAll(Map<String, String>.from(json['environment'] ?? {}));
    p.extraEnvironment = json['extraEnvironment'] as String? ?? '';
    return p;
  }
}

Iterable<String> lines(String text) =>
    text.split('\n').map((v) => v.trim()).where((v) => v.isNotEmpty);

String quoteArgument(String value) {
  if (value.isNotEmpty && !RegExp(r'[\s"&|<>^%$`]').hasMatch(value))
    return value;
  final escaped = value
      .replaceAllMapped(RegExp(r'(\\*)"'), (m) => '${m[1]}${m[1]}\\"')
      .replaceAllMapped(RegExp(r'\\+$'), (m) => '${m[0]}${m[0]}');
  return '"$escaped"';
}

String displayCommand(String executable, List<String> arguments) =>
    '& ${[executable, ...arguments].map((v) => "'${v.replaceAll("'", "''")}'").join(' ')}';
