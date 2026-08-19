# Qwen3-VL-2B — Vision LLM di Termux (HP Android)

Vision LLM lokal di HP Android (Termux): server OpenAI-compatible, web UI, CLI streaming, auto-resize gambar, model terpilih: **Qwen3-VL-2B** (official GGUF). Berbasis fork `tether-ai-research/qvac-visionpsy-nano` (llama.cpp patched + libmtmd).

## Cara pakai

```bash
kei                # alias → menu: 1 start server, 2 stop, 3 web UI, 4 chat CLI, 5 query
visionpsy img <foto> "<prompt>"   # one-shot: contoh deskripsi gambar
```

- Web UI: `http://<IP-WiFi>:8091` (canvas resize 1024px + JPEG 75% otomatis)
- API OpenAI-compatible: `http://<IP-WiFi>:8090/v1/chat/completions` (CORS on)
- Server di-detach (`setsid` + `disown`), tahan hidup walau CLI keluar; `termux-wake-lock`

## Model

`models/qwen3-vl-2b/model.gguf` (Q4_K_M 1.1GB) + `mmproj.gguf` (Q8_0 425MB) dari `Qwen/Qwen3-VL-2B-Instruct-GGUF`.

| Fitur | Hasil (TECNO LJ8k, 4×A76 @2.5GHz, RAM 7.3GB) |
|---|---|
| Chat teks | **1-4 detik**, bahasa Indonesia bagus |
| Baca gambar (12MP, auto-resize 640px) | **21-27 detik** |
| Akses web/LAN | http://<IP>:8090 (API) & :8091 (UI) |

Konfigurasi per-model: `models/<nama>/maxpx` (maxpx resize, qwen3 = 640). Model aktif: `models/current.txt`.

## Optimasi kecepatan (penting!)

Kombinasi yang menurunkan waktu gambar 2 menit → **21-27 detik**:

- `MTMD_DISABLE_BATCH_SLICES=1` — matikan slicing grafik vision di libmtmd (overhead slicing > hemat RAM di HP ini)
- `-b 2048 -ub 1024` — batch prompt lebih besar
- `-t 4 -C 0xF0` — pin ke 4 big cores (A76); salah set thread = 10-18× lambat di big.LITTLE
- `MTMD_NO_UPSCALE=1` + resize client-side (Pillow/canvas, JPEG 75%)

Model yang pernah diuji & digugurkan: `visionpsy-nano` (460M — chat echo/lemah, vision cepat 15s), `qwen2-vl-2b` (vision 2-5 menit, encoder 678MB terlalu berat), `gemma4-e2b` (terbaik di benchmark edge tapi 3.1GB+1GB > RAM HP).

## Dari riset internet (Juli-Agustus 2026)

- **Gemma 4 E2B / E4B** (rilis April 2026, Apache-2.0, 140+ bahasa): VLM edge terbaik menurut 3 benchmark independen (Jetson industrial, PhotoPrism, XDA). Vision encoder MobileNet-V5 → cuma ~200 token prompt/gambar (5-8× lebih ringan dari keluarga Qwen VL) → prefill sangat cepat. **TAPI**: Q4_K_M 3.1 GB + mmproj ~1 GB → butuh ≥4GB RAM.
- SmolVLM2-2.2B: paling cepat (Jetson 12.8s) tapi output "generik/placeholder".
- Qwen2.5-VL-3B: juara OCR (arch `qwen2.5vl` tidak ada di fork ini).
- Llama.cpp perlu build ≥ b8637 untuk arch `gemma4`; fork ini sudah incl. `gemma4v` via mtmd.
- MTP draft (spec-decode) untuk E2B/E4B sudah masuk upstream llama.cpp (PR #24282).

## Catatan build Termux (aarch64)

- Stub `spawn.h` wajib (Termux tidak punya): `/data/data/com.termux/files/usr/include/spawn.h` (posix_spawn*).
- Build: `cmake -DGGML_CUDA=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_APP=OFF -DLLAMA_BUILD_UI=OFF`, target `llama-server` + `llama-mtmd-cli`.
- `llama-server` butuh UI assets; kalau HF download gagal, buat dummy di `tools/ui/dist/` (index.html, loading.html, manifest.webmanifest, sw.js, build.json, version.json, bundle.js, bundle.css, workbox.js).
- GPU accel: **Vulkan bisa jalan tanpa root** (paket `vulkan-loader-android` Termux auto-detect `vulkan.mali.so` sistem) — TAPI di Mali-G615 MC2 ggml-vulkan justru 4-24× LEBIH LAMBAT dari CPU (prompt 5.5 vs 19.2 t/s, gen 5.9 vs 10.7 t/s; prompt pertama ~0.8 t/s karena kompilasi shader). OpenCL: driver `libOpenCL.so` ada tapi di-*block* linker namespace Android (dlopen `/vendor` gagal dari Termux). Kesimpulan: CPU tetap juara; GPU tidak menolong di Mali murah.
- HF download: `huggingface_hub` pip gagal (hf-xet build), pakai `curl -L` langsung.

## Struktur fork (llama.cpp patched)

- `libmtmd` (tools/mtmd) = encoder multimodal: mendukung visionpsy, qwen2vl, qwen3vl, gemma4v, llava, minicpmv, pixtral, internvl, glm4v, cogvlm, hunyuan-vl, momo-vl, dll. — semua bisa lewat `--mmproj` yang cocok.
- Arch "visionpsy" (nanoVLM/peg) hanya ada di fork ini; GGUF standard tidak mengenalnya.

## Fitur dalam repo

- `vision_server.sh` — start/stop/status/web/cli/query; reads `models/current.txt`
- `visionpsy-menu.sh` — menu: start/stop/web/chat/query
- `visionpsy` — one-shot CLI (start server kalau belum, auto-reconnect)
- `web/cli.py` — chat CLI streaming (http.client persistent, `/img`, `/sys`, `/clr`, `/t`, `/help`)
- `web/index.html` — web UI (canvas resize, streaming, lightbox)
- `resize.py` — Pillow resize JPEG (dipakai query)