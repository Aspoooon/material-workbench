# Third-party notices

## FFmpeg / FFprobe 8.0

Copyright © 2000–2025 the FFmpeg developers and respective source-file authors.

- Project: https://ffmpeg.org/
- Unmodified corresponding source: `Runtime/ffmpeg-8.0-source.tar.xz`
- Official origin: https://ffmpeg.org/releases/ffmpeg-8.0.tar.xz
- Source SHA-256: `b2751fccb6cc4c77708113cd78b561059b6fa904b24162fa0be2d60273d27b8e`
- License of this build: **LGPL-2.1-or-later**, as reported by `ffmpeg -L`.
- License text: `Runtime/COPYING.LGPLv2.1`. The complete source archive also contains per-file notices and other applicable licenses.
- Build instructions and complete configure options: `scripts/build-runtime.sh`.

The build does not enable GPL, version3 or nonfree options and does not link x264 / x265 or Homebrew libraries. FFmpeg / FFprobe are invoked as separate command-line processes; the Swift application does not link to libav*.

Each distributed App bundles the corresponding FFmpeg source archive and LGPL text under `Contents/Resources/Licenses/`. The source archive is also available in this repository. The bundled executables retain their FFmpeg attribution. Users may rebuild or replace the tools; modifying a signed App may require locally re-signing it.

The application MIT license does not replace or restrict FFmpeg's licenses or recipients' rights under them. This project and FFmpeg are provided without warranty. Codec patent questions, if applicable to a distributor's use or jurisdiction, are separate from copyright licensing.

## Apple frameworks

SwiftUI, AppKit, AVFoundation, VideoToolbox, Image I/O, Core Graphics, Core Image and PDFKit are system frameworks provided by macOS. No Apple framework binaries are redistributed in this repository.

## Design and research references

Morph, Kompakt, Clop, HandBrake and SwiftUI Expert Skill were consulted as research references. Their application code and assets are not included in the project's original code. They are not dependencies or endorsements.
