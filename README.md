# AnyPS5 Studio

Interface Flutter desktop para Windows, em português. Inicie com `Iniciar AnyPS5.cmd` na raiz do projeto. O executável compilado está em `gui/build/windows/x64/runner/Release/anyps5_gui.exe`; mantenha `data/` e `flutter_windows.dll` ao lado dele.

Após clonar do GitHub, o lançador baixa os binários oficiais v0.1.3 e confere seus hashes SHA-256 antes de compilar e iniciar a interface. Os binários, caches, configurações pessoais e arquivos de jogos ficam fora do controle de versão. Também é possível preparar os binários manualmente com `powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup_gui.ps1`, a partir da raiz.

## Uso

1. Selecione o ELF de entrada e o executável de saída.
2. Escolha Windows, Linux ou macOS e ajuste as opções nas abas Conversão e Avançado.
3. Clique em Converter executável. O comando e o resultado aparecem no painel inferior.
4. Para rodar uma saída Windows, copie as bibliotecas pelo botão da aba Conversão e coloque os recursos originais do título em `app0/`, ao lado da saída. Consulte `docs/user/USAGE.md` na raiz.
5. Ajuste GPU, idioma, apresentação e cache na aba Execução e clique em Executar saída.

As opções repetidas recebem um valor por linha, sem aspas. Caminhos relativos de conversão usam a raiz do projeto. Diretórios extras de módulos e executáveis adicionais são relativos à pasta pai dos módulos. Variáveis de ambiente afetam somente o processo iniciado. Campos vazios mantêm valores herdados do ambiente.

Perfis JSON podem ser salvos e abertos; o último perfil executado é restaurado de `%LOCALAPPDATA%/AnyPS5Gui/last-profile.json`. O modo Verificar patches não grava uma saída. Arquivos de saída existentes exigem confirmação antes de serem substituídos. A cópia de bibliotecas preserva arquivos existentes.

O código-fonte AnyPS5 está na raiz, clonado de https://github.com/boykopovar/AnyPS5. O relinker e as bibliotecas Windows oficiais v0.1.3 estão em `downloads/`. A interface consulta `--help` para reconhecer parâmetros oferecidos pelo binário escolhido. Submódulos do núcleo não foram inicializados; são necessários somente para compilar o núcleo completo. A interface usa apenas o SDK Flutter e diálogos nativos Windows.

## Desenvolvimento

```powershell
cd gui
$env:PUB_CACHE = "$PWD/../downloads/pub-cache"
flutter pub get
flutter run -d windows
flutter test
flutter analyze
flutter build windows --release
```

Testes incluem validação de conflitos, perfis, caminhos com espaços, comunicação com o relinker local e navegação/layout. Execução de jogos depende da compatibilidade do AnyPS5 e de recursos fornecidos pelo usuário.

---

# About

Tool for automatic executables porting to Linux and Windows.

The relinker-only build runs on macOS, including Apple silicon.

[**Web converter**](https://boykopovar.github.io/AnyPS5/) - files stay on your device.

![anyps5_collage1](https://github.com/user-attachments/assets/ed2f0b2d-33d3-46d7-ab88-767ca872fc99)

Includes a [relinker](core/relinker) that converts executable to the target system's native format and implementations of [system prx libraries](core/libs/prx) suitable for dynamic linking. No emulation or separate runtime process.

[**Discord**](https://discord.gg/BHFztBPUe), [Usage](docs/user/USAGE.md), [Build instructions](docs/dev/BUILD.md), [Architecture](docs/dev/ARCHITECTURE.md), [Technical debt of the project](docs/dev/TechnicalDebt.md), [code style conventions](docs/dev/CONVENTIONS.md), [contributing](CONTRIBUTING.md)

## Status

[![libraries](https://boykopovar.github.io/AnyPS5/badge-libraries.svg)](https://boykopovar.github.io/AnyPS5/progress.html) [![shaders](https://boykopovar.github.io/AnyPS5/badge-shaders.svg)](https://boykopovar.github.io/AnyPS5/progress.html)

[![progress map](https://boykopovar.github.io/AnyPS5/progress.svg)](https://boykopovar.github.io/AnyPS5/progress.html)

[Progress history](https://boykopovar.github.io/AnyPS5/history.html)

<sub>* System libraries: percentage of the functions known to the project so far (declared in [core/libs/prx](core/libs/prx)), not of every PS5 system function. The total grows as more functions are declared.</sub>

Unsupported or unexpected states strictly throw `std::runtime_error`. `what()` is printed to stderr and the process terminates.

The [shader recompiler](core/shader/recompiler/Recompiler.cpp) successfully produces SPIR-V (validated via [Spirv-Tools](3rdparty/SPIRV-Tools) when built with `ANYPS5_ENABLE_SPIRV_TOOLS`).

## Compatibility

Per-game status and test reports live in the [Game bring-up](https://github.com/boykopovar/AnyPS5/discussions/categories/game-bring-up) discussions, one thread per title.

## Input mapping

SDL-mapped game controllers are supported, including analog sticks and triggers. Keyboard and mouse controls can be configured with an `anyps5-input.ini` file. See [input mapping](docs/user/INPUT_MAPPING.md) for the supported devices and configuration format.

## Disclaimer

This project is intended for interoperability, research, preservation, and compatibility purposes. It does not include, distribute, or require copyrighted software, firmware, cryptographic keys, or proprietary libraries. Users are responsible for ensuring that any binaries used with this project are obtained and used in accordance with applicable laws and their respective license terms.

AnyPS5 is an independent project and is not affiliated with, authorized or endorsed by Sony Interactive Entertainment. "PlayStation" and "PS5" are trademarks of Sony Interactive Entertainment Inc.

## License

This project is licensed under the GNU General Public License version 2 only.
