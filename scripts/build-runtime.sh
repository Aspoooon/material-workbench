#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
WORK=$(mktemp -d /tmp/material-ffmpeg.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
tar -xf "$ROOT/Runtime/ffmpeg-8.0-source.tar.xz" -C "$WORK"
cd "$WORK/ffmpeg-8.0"
./configure --prefix=/opt/material-workbench-ffmpeg --disable-doc --disable-debug --disable-ffplay --disable-network --disable-autodetect --enable-videotoolbox --enable-audiotoolbox --enable-filter=boxblur --disable-x86asm
make -j8
make install DESTDIR="$WORK/stage"
cp "$WORK/stage/opt/material-workbench-ffmpeg/bin/ffmpeg" "$WORK/stage/opt/material-workbench-ffmpeg/bin/ffprobe" "$ROOT/Runtime/"
