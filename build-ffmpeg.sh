#!/bin/bash
# Builds static, universal (arm64 + x86_64), LGPL-only ffmpeg and ffprobe for bundling in Streamer.app.
#
#   Scripts/build-ffmpeg.sh            # -> Vendor/ffmpeg/{ffmpeg,ffprobe}
#
# Encoding uses Apple's VideoToolbox (H.264/HEVC) and the native AAC/E-AC-3 encoders, so no GPL
# components (x264/x265) are needed and the result can be redistributed under the LGPL v2.1.
# Requirements: Xcode command line tools, nasm (brew install nasm) for x86_64 assembly, pkg-config.
set -euo pipefail

FFMPEG_VERSION="${FFMPEG_VERSION:-7.1.1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/ffmpeg"
OUT="$ROOT/Vendor/ffmpeg"
MIN_MACOS="15.0"
JOBS="$(sysctl -n hw.ncpu)"

mkdir -p "$WORK" "$OUT"
cd "$WORK"
if [[ ! -d "ffmpeg-$FFMPEG_VERSION" ]]; then
  curl -fL "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" -o "ffmpeg-$FFMPEG_VERSION.tar.xz"
  tar xf "ffmpeg-$FFMPEG_VERSION.tar.xz"
fi

COMMON_FLAGS=(
  --disable-gpl --disable-nonfree --disable-version3
  --enable-static --disable-shared
  --disable-doc --disable-debug --disable-ffplay
  --disable-autodetect
  --enable-videotoolbox --enable-audiotoolbox
  --enable-securetransport --enable-zlib --enable-bzlib --enable-iconv
  --disable-sdl2 --disable-xlib --disable-libxcb
  --enable-pthreads
  # Encode audio only with Apple's AudioToolbox (aac_at), which is covered by Apple's codec
  # licenses. FFmpeg's own AAC and Dolby encoders are left out of the commercial App Store build.
  --disable-encoder=aac,ac3,ac3_fixed,eac3,mp2,dca,truehd,mlp
)

for ARCH in arm64 x86_64; do
  BUILD="$WORK/build-$ARCH"
  rm -rf "$BUILD"
  mkdir -p "$BUILD"
  cd "$BUILD"
  EXTRA=()
  if [[ "$ARCH" == "x86_64" ]] && ! command -v nasm >/dev/null; then EXTRA+=(--disable-x86asm); fi
  "$WORK/ffmpeg-$FFMPEG_VERSION/configure" \
    --prefix="$BUILD/install" \
    --arch="$ARCH" --target-os=darwin --enable-cross-compile \
    --cc="clang -arch $ARCH" \
    --extra-cflags="-mmacosx-version-min=$MIN_MACOS" \
    --extra-ldflags="-mmacosx-version-min=$MIN_MACOS" \
    --extra-libs="-liconv" \
    "${COMMON_FLAGS[@]}" ${EXTRA[@]+"${EXTRA[@]}"}
  make -j"$JOBS"
  make install
  cd "$WORK"
done

for BIN in ffmpeg ffprobe; do
  lipo -create "$WORK/build-arm64/install/bin/$BIN" "$WORK/build-x86_64/install/bin/$BIN" -output "$OUT/$BIN"
  chmod +x "$OUT/$BIN"
done

# Keep the license and exact source version next to the binaries (LGPL compliance).
cp "$WORK/ffmpeg-$FFMPEG_VERSION/COPYING.LGPLv2.1" "$OUT/"
echo "$FFMPEG_VERSION" > "$OUT/VERSION"
"$OUT/ffmpeg" -hide_banner -buildconf | grep -q -- "--enable-gpl" && { echo "error: GPL build detected"; exit 1; }
echo "Built LGPL ffmpeg $FFMPEG_VERSION into $OUT"
"$OUT/ffmpeg" -hide_banner -encoders | grep -E "videotoolbox|_at"
"$OUT/ffmpeg" -hide_banner -encoders | grep -qE " (eac3|ac3) " && { echo "error: Dolby encoders must not be built"; exit 1; }
true
