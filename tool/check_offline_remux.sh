#!/usr/bin/env bash
# 离线合并验证（插件路径版）：
# 不再编译 / 运行原生 Aether 的 OfflineVideoRemuxer（该库缺失 mp4/mov muxer，已废弃）。
# 改为用系统 ffmpeg 执行与 Dart 插件路径（ffmpeg_kit_flutter_new）完全一致的命令，
# 覆盖「明文 TS」与「AES-128 加密 TS」两种真实下载形状，验证 MP4 封装与解密正确。
set -euo pipefail
cd "$(dirname "$0")/.."
command -v ffmpeg >/dev/null 2>&1 || brew install ffmpeg
command -v ffprobe >/dev/null 2>&1 || brew install ffmpeg

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# 生成一段带音视频的 TS 测试流（明文），并产出一条与插件命令一致的合并命令。
# 该命令为 Dart 端视频合并所用，确保 CI 能回归校验插件合并逻辑。
make_plain() {
  local dir="$1"
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i testsrc2=size=96x64:rate=10 \
    -f lavfi -i sine=frequency=440:sample_rate=48000 \
    -t 4 -c:v libx264 -pix_fmt yuv420p -g 10 -c:a aac \
    -f hls -hls_time 1 -hls_playlist_type vod \
    "$dir/index.m3u8"
}

# 生成 AES-128 加密的 TS 流。无显式 IV 时按 HLS 规范用 Media-Sequence 作隐式 IV，
# 与 LumeBox 真实下载的内容一致；只有带 crypto 协议的 FFmpeg 才能正确解密。
make_encrypted() {
  local dir="$1"
  head -c 16 /dev/urandom > "$dir/key.bin"
  printf 'key.bin\n%s\n' "$dir/key.bin" > "$dir/key-info"
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i testsrc2=size=96x64:rate=10 \
    -f lavfi -i sine=frequency=440:sample_rate=48000 \
    -t 4 -c:v libx264 -pix_fmt yuv420p -g 10 -c:a aac \
    -f hls -hls_time 1 -hls_playlist_type vod \
    -hls_key_info_file "$dir/key-info" \
    "$dir/index.m3u8"
}

# 执行 Dart 插件路径使用的同一条 ffmpeg 命令（流拷贝，无转码）。
merge_plugin() {
  local dir="$1"
  ffmpeg -hide_banner -loglevel error -nostdin -y \
    -protocol_whitelist file,crypto,data -allowed_extensions ALL \
    -i "$dir/index.m3u8" \
    -map 0:v:0 -map '0:a?' -c copy \
    -avoid_negative_ts make_zero -movflags +faststart \
    -f mp4 "$dir/merged.mp4.part"
}

verify_mp4() {
  local out="$1" label="$2"
  local types
  types=$(ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "$out")
  echo "$types" | grep -q '^video$' || { echo "[$label] 缺视频轨道"; return 1; }
  echo "$types" | grep -q '^audio$' || { echo "[$label] 缺音频轨道"; return 1; }
  local dur
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out")
  # 4s 源时长应落在 [3.8, 4.3] 区间。
  awk -v d="$dur" 'BEGIN { exit !(d>=3.8 && d<=4.3) }' || {
    echo "[$label] 时长异常: $dur"; return 1; }
  echo "[$label] OK (${dur}s)"
}

# 明文 TS
PLAIN="$WORK/plain"; mkdir -p "$PLAIN"
make_plain "$PLAIN"
merge_plugin "$PLAIN"
verify_mp4 "$PLAIN/merged.mp4.part" plain

# AES-128 加密 TS（隐式 IV）
ENC="$WORK/encrypted"; mkdir -p "$ENC"
make_encrypted "$ENC"
merge_plugin "$ENC"
verify_mp4 "$ENC/merged.mp4.part" encrypted

echo "离线 MP4 合并（插件路径）全部通过 ✓"
