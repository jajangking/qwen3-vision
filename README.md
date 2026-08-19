# VisionPsy-Nano — Termux Multipurpose Vision Setup

Vision LLM local di HP Android (Termux) dengan **model switcher**, web UI, CLI streaming, dan auto-resize gambar. Berbasis fork `tether-ai-research/qvac-visionpsy-nano` (llama.cpp patched + libmtmd).

## Cara pakai

```bash
kei                # alias → menu: 1 start server, 2 stop, 3 web UI, 4 chat CLI, 5 query, 7 ganti model
visionpsy img <foto> "<prompt>"   # one-shot: contoh deskripsi gambar
```

- Web UI: `http://<IP-WiFi>:8091` (canvas resize 1024px + JPEG 75% otomatis)
- API OpenAI-compatible: `http://<IP-WiFi>:8090/v1/chat/completions` (CORS on)
- Server di-detach (`setsid` + `disown`), tahan hidup walau CLI keluar; `termux-wake-lock`

## Model yang didukung (folder `models/<nama>/model.gguf` + `mmproj.gguf`)

| Model | Ukuran | Chat teks | Baca gambar | Status |
|---|---|---|---|---|
| `visionpsy-nano` (default) | 460M (Q4_K_M) | buruk (echo) | **~12-15 detik** | ✅ jalan |
| `qwen3-vl-2b` | 2B (Q4_K_M) | **~1 detik, Indonesia bagus** | ~2 menit (auto-resize 640px) | ✅ jalan |
| `qwen2-vl-2b` | 2B (Q4_K_M) | sedang | 2-5 menit | ❌ terlalu lambat |

- Konfigurasi per-model: `models/<nama>/maxpx` (ukuran max resize gambar, default 1024)
- Model aktif: `models/current.txt`
- Sumber: `qvac/VisionPsy-Nano-460M-GGUFs`, `ggml-org/Qwen2-VL-2B-Instruct-GGUF`, `Qwen/Qwen3-VL-2B-Instruct-GGUF`

## Dari riset internet (Juli-Agustus 2026)

- **Gemma 4 E2B / E4B** (rilis April 2026, Apache-2.0, 140+ bahasa): VLM edge terbaik menurut 3 benchmark independen (Jetson industrial, PhotoPrism, XDA). Vision encoder MobileNet-V5 → cuma ~200 token prompt/gambar (5-8× lebih ringan dari keluarga Qwen VL) → prefill sangat cepat. **TAPI**: Q4_K_M 3.1 GB + mmproj ~1 GB → butuh ≥4GB RAM, tidak muat di HP 7.3GB/2GB-free ini.
- SmolVLM2-2.2B: paling cepat (Jetson 12.8s) tapi output "generik/placeholder".
- Qwen2.5-VL-3B: juara OCR, (arch `qwen2.5vl` tidak ada di fork ini).
- Llama.cpp perlu build ≥ b8637 untuk arch `gemma4`; fork ini sudah incl. `gemma4v` via mtmd.
- MTP draft (spec-decode) untuk E2B/E4B sudah masuk upstream llama.cpp (PR #24282).

## Catatan build Termux (aarch64)

- Stub `spawn.h` wajib (Termux tidak punya): `/data/data/com.termux/files/usr/include/spawn.h` (posix_spawn*).
- Build: `cmake -DGGML_CUDA=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_APP=OFF -DLLAMA_BUILD_UI=OFF`, target `llama-server` + `llama-mtmd-cli`.
- `llama-server` butuh UI assets; kalau HF download gagal, buat dummy di `tools/ui/dist/` (index.html, loading.html, manifest.webmanifest, sw.js, build.json, version.json, bundle.js, bundle.css, workbox.js).
- GPU accel (Vulkan/OpenCL) tidak mungkin: driver Mali terkunci, butuh root.
- big.LITTLE (4× A76 @2.5GHz + 4× A55 @2.0GHz): pin `-t 4 -C 0xF0` (bug: salah set thread = 10-18× lambat).
- `MTMD_NO_UPSCALE=1` + resize client (1024px, JPEG 75) memangkas waktu 54s → 15s di VisionPsy-Nano.
- HF download: `huggingface_hub` pip gagal (hf-xet build), pakai `curl -L` langsung.

## Struktur fork (llama.cpp patched)

- `libmtmd` (tools/mtmd) = encoder multimodal: mendukung visionpsy, qwen2vl, qwen3vl, gemma4v, llava, minicpmv, pixtral, internvl, glm4v, cogvlm, hunyuan-vl, momo-vl, dll. — semua bisa lewat `--mmproj` yang cocok.
- Arch "visionpsy" (nanoVLM/peg) hanya ada di fork ini; GGUF standard tidak mengenalnya.

## Fitur dalam repo

- `vision_server.sh` — start/stop/status/web/cli/query; reads `models/current.txt`
- `visionpsy-menu.sh` — menu: start/stop/web/chat/query/ganti model
- `visionpsy` — one-shot CLI (start server kalau belum, auto-reconnect)
- `web/cli.py` — chat CLI streaming (http.client persistent, `/img`, `/sys`, `/clr`, `/t`, `/help`)
- `web/index.html` — web UI (canvas resize, streaming, lightbox)
- `resize.py` — Pillow resize JPEG (dipakai query)