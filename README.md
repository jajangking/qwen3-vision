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
- HF download: `huggingface_hub` pip gagal (hf-xet build), pakai `curl -L` langsung.

## Eksperimen GPU & tuner model (Agustus 2026) — semuanya diuji, hasil: CPU tetap juara

### 1. Vulkan — jalan tanpa root, tapi MALAH lambat

- Paket Termux: `vulkan-loader-android` (+ `vulkan-tools`) → auto-detect driver sistem. `vulkaninfo` = **Mali-G615 MC2** asli (bukan llvmpipe palsu).
- Mainline `llama-cpp` + `llama-cpp-backend-vulkan` (b10290, prebuilt, tidak perlu compile) langsung jalan dengan `-ngl 99` dan mendukung model kita (qwen3vl/mtmd).
- Hasil benchmark di Mali-G615 MC2: prompt **5.5 t/s vs CPU 19.2 t/s**, gen **5.9 vs 10.7 t/s** → GPU **4-24× lebih lambat** (prompt pertama 0.8 t/s, biaya kompilasi shader). Sama dengan laporan RK3588 (CPU 1.5s vs Vulkan 24s) dan diskusi ggml #9464 — ggml-vulkan dirancang untuk GPU desktop, jelek di Mali murah.

### 2. OpenCL — diblokir sistem

- Driver `libOpenCL.so` ADA di `/vendor/lib64/`, ICD loader Termux (`ocl-icd`) terpasang, `clinfo` → "Number of platforms 0".
- Akar masalah: dlopen `/vendor/lib64/libOpenCL.so` dari Termux ditolak **linker namespace** Android (`dlopen failed: not accessible for the namespace "(default)"`). Vulkan lolos karena loader-nya jalan lewat jalur sistem; OpenCL tidak punya jalur itu.

### 3. Tuner level model

| Percobaan | Hasil |
|---|---|
| `MTMD_FORCE_BATCH=4096` (knob batch vision) | 18.0/10.7 t/s vs baseline 21.9/12.2 → **lebih lambat 3s** |
| `--cache-type-k q8_0 --cache-type-v q8_0` | **crash saat boot** (fork tidak support, mati diam-diam) |
| Re-quant `IQ4_XS` dari Q4_K_M | dilarang llama.cpp ("requantizing from type q4_K is disabled"); harus download Q8 2GB dulu, estimasi gain ~1s → tidak worth |
| `-t 8` (8 thread, semua core) | 75s total (gen 1.6 t/s) → 3× lebih lambat, big.LITTLE contention |
| `-b 2048 -ub 1024` + slices off + `-t 4 -C 0xF0` | **PEMENANG 21-27s** (satu-satunya yang lebih cepat) |

Kesimpulan: 21s (encode ~15s + gen ~6s) = batas fisik 4×A76 untuk Qwen3-VL-2B. Di bawah itu butuh hardware beda; speculative decode (draft ~300MB) belum dicoba, estimasi hemat 1-2s saja.

### 4. Bug seru: `pkill -f` membunuh shell sendiri

Gejala: command yang berisi `pkill -9 -f "llama-s[e]rver"` + teks `llama-server` di baris yang sama (mis. untuk start ulang) hang tanpa output, seolah "stuck" — padahal tool/shell-nya **bunuh diri**.

Penjelasan: shell wrapper dijalankan sebagai `bash -c '<seluruh command>'`, jadi cmdline proses wrapper mengandung teks literal `llama-server`. Regex `llama-s[e]rver` cocok dengan cmdline itu → `pkill -f` menembak proses sendiri, sesi mati.

Solusi: `pkill -9 -x llama-server` — `-x` mencocokkan **nama proses persis** (comm `llama-server`), bukan teks cmdline, jadi aman dipakai di command mana pun. Alias aman lain: `pkill -f "llama-serve[r]"` (trik bracket tetap berfungsi selama literal nama binary tidak ikut tertulis di command).
- HF download: `huggingface_hub` pip gagal (hf-xet build), pakai `curl -L` langsung.

## Struktur fork (llama.cpp patched)

- `libmtmd` (tools/mtmd) = encoder multimodal: mendukung visionpsy, qwen2vl, qwen3vl, gemma4v, llava, minicpmv, pixtral, internvl, glm4v, cogvlm, hunyuan-vl, momo-vl, dll. — semua bisa lewat `--mmproj` yang cocok.
- Arch "visionpsy" (nanoVLM/peg) hanya ada di fork ini; GGUF standard tidak mengenalnya.

## Fitur dalam repo

- `vision_server.sh` — start/stop/status/web/cli/query; reads `models/current.txt`
- `visionpsy-menu.sh` — menu: start/stop/web/chat/query
- `visionpsy` — one-shot CLI (start server kalau belum, auto-reconnect)
- `web/cli.py` — chat CLI streaming (http.client persistent, `/img`, `/sys`, `/clr`, `/t`, `/help`)
- `web/index.html` — web UI (canvas resize, streaming, lightbox, scan animasi, AGENT tool-calling)
- `resize.py` — Pillow resize JPEG (dipakai query)
## Tool calling (Agent) — Agustus 2026

Model (Qwen3-VL-2B via OpenAI function-calling) bisa memanggil tool yang dieksekusi LOKAL di browser:

- `detect_objects` — COCO-SSD (TensorFlow.js + WebGL, GPU Mali) → bounding box digambar di atas foto, koordinat ASLI dikembalikan ke model → jawaban grounded ke deteksi sungguhan (model sendiri TIDAK bisa grounding pixel).
- `get_time` — tanggal/waktu sekarang + timezone.
- `web_search` — DuckDuckGo Instant Answer API (+fallback Wikipedia), tanpa API key.
- `calculate` — parser matematika aman (regex-whitelist, tanpa eval mentah).
- `take_photo` — getUserMedia: kamera HP dibuka, foto diambil, dilampirkan ke percakapan.

Loop: model panggil tool → UI eksekusi di browser → hasil ({tool_call_id}) dikembalikan → model lanjut sampai jawaban final (maks 4 ronde). Deteksi manual: tombol 🎯.

## Riset model coding kecil-kekuatan (Agustus 2026) — ditampung

Pertanyaan: model AI coding open-source terbaik yang ringan & muat HP (TECNO LJ8k:
7.3GB RAM, A76+A55, CPU-only efektif, llama.cpp b10290 sudah ada).

### Peta lanskap per kelas ukuran
| Kelas        | Model terbaik                                          | Skor kunci                                  | Muat HP-mu? |
|--------------|--------------------------------------------------------|---------------------------------------------|-------------|
| 1B           | mini-coder-1.7b; MiniCPM5-1B                           | SWE 18.6 (kalah SWE-agent-LM 7B=15.2)       | ya (paling pas) |
| 3-4B         | mini-coder-4b; Phi-4-mini 3.8B; Qwen3-4B-2507; Gemma 4 E4B | SWE 26.8 ≈ gpt-oss-120b; BFCL 0.50-0.88  | ketat tapi muat |
| 7-8B         | IBM Granite 4.1 8B                                    | BFCL 0.68, butuh 10-12GB RAM                | tidak |
| 24B+ lokal   | Devstral Small 2; Gemma 4 31B; Qwen3.6 27B/35B-A3B    | SWE 68-77                                   | tidak (butuh GPU) |
| Frontier/API | DeepSeek V4 Pro/Flash; Kimi K2.6/2.7; GLM-5.x; Qwen3-Coder-Next 80B-A3B | SWE 70-80+                     | server/GPU |

### Aturan main (dari BFCL/SWE-bench/agentic 2026)
1. **Lantai keandalan tool-calling ≈ 4B** — di bawah itu pakai specialist
   fine-tune (mini-coder) bukan generalist; Qwen3.5: 2B=0.436, 4B=0.503, 9B=0.661.
2. **Kuantisasi jangan di bawah Q5 untuk agen** — Q4 turun ~4-6 poin tool-call
   validity, Q3 tidak layak. Q6 lebih baik lagi kalau muat.
3. **Grammar-constrained decoding** (llama.cpp `--grammar` / Outlines / Guidance)
   memotong kegagalan tool-call hampir setengah (84.7%->97% utk Granite 4.1 8B Q4).
4. **Konteks kecil = ringkas** — model kecil ambruk di 32-48k; summarization
   scrollback tiap ~10 turn mengalahkan jendela konteks panjang mentah.
5. Param count prediktor lemah di bawah 8B (non-monotonik) — nilai per-benchmark,
   bukan per-parameter.

### Shortlist untuk hp ini
- **Pilihan utama**: `mini-coder-4b Q4_K_M` (~2.6GB) — SWE-bench 26.8 ≈ gpt-oss-120b,
  muat di 7.3GB. Sumber GGUF: HF `mradermacher/TinyQwen3-distill-4B-coder-GGUF` /
  distilat asli `ricdomolm/mini-coder-4b` (Q8_0 `4iqq/mini-coder-4b-Q8_0-GGUF` 4.28GB).
- **Paling ngebut**: `mini-coder-1.7b` Q8_0 1.83GB (`sizzlebop/mini-coder-1.7b-Q8_0-GGUF`)
  atau IQ4_NL 1.05GB.
- Cadangan matang: Phi-4-mini 3.8B (MIT, native tool token, Q4 2.5GB, `unsloth/Phi-4-mini-instruct-GGUF`).
- Semua pakai template Qwen3/ChatML — jalan di mainline llama.cpp (bukan fork mtmd vision).
- Integrasi: taruh di `~/visionpsy/models/<nama>/model.gguf` (tanpa mmproj) + `cli.py`
  base server OpenAI-compatible yang sama.

### Status
Ditampung (belum diunduh/dipasang). Download menunggu keputusan user.

### Survey semua ukuran: model coding terkuat 2026 (DeepSeek V4 dkk)
Diverifikasi HF Agustus 2026.

| Model | Ukuran (total/aktif) | SWE Verified | Ctx | Lisensi | Muat lokal? |
|---|---|---|---|---|---|
| DeepSeek-V4-Pro | 1.6T / 49B | 80.6% vendor; 96.4% Vals-0813 | 1M | MIT | 8xH100 (tidak) |
| DeepSeek-V4-Flash | 284B / 13B | 79.0% | 1M | MIT | 4-bit ~170GB (tidak) |
| Kimi K3 | 2.8T MoE | 93.4% (Vals); #1 Frontend | 1M | open weights ±Jul-27 | API |
| GLM-5.2 | 744B / 40B | 82.8% (Vals) | 1M | MIT | API |
| MiniMax M3 | ~230B / ~10B | 80.5% | ~1M | Community | API |
| Qwen3.8 Max | besar | top open BenchLM | 1M | open | API |
| Qwen3-Coder-Next | 80B / 3B | 70.6% | 256K | Apache-2.0 | ~46GB (paling layak self-host) |
| Qwen3.6-27B | 27B dense | 77.2% | ? | Apache-2.0 | 32GB Mac |
| Kimi K2.7-Code | 1T / 32B | 78.2% | ? | ? | rig 512GB |
| Hunyuan Hy3 | besar | 78% | ? | Apache-2.0 | API |
| gpt-oss-120b | 117B / 5.1B | ~26-30% | 128K | Apache-2.0 | ~64GB Q4 |

GGUF resmi komunitas: `unsloth/DeepSeek-V4-Flash-0731-GGUF` (UD-IQ1 s/d Q4_K).
Catatan CAISI (NIST): V4-Pro ketinggalan frontier ±8 bln di pengukuran independen (SWE 74%).
Kesimpulan buat HP: semua kelas besar tidak muat; tetap mini-coder-1.7b/4b (headline riset di atas).

### Explorasi luas: kandidat kecil terbaru (Agustus 2026) — diverifikasi HF
| Model | Rilis | Vision | Ukuran Q4 | t/s HP | Tool | GGUF |
|---|---|---|---|---|---|---|
| Qwen3.5-4B | Feb-26 | ya (video) | 2.74GB | 12-15 | BFCL 50.3 | unsloth/Qwen3.5-4B-GGUF ✅ + mmproj |
| LFM2.5-VL-3B (Liquid) | 12-Agu-26 | ya | ~3GB | 20 (S26) | TS 59.5, BFCL 32.5 | LiquidAI/LFM2.5-VL-3B-GGUF ✅ 10 GGUF + 3 mmproj |
| LFM2.5-2.6B (Liquid) | Agu-26 | tidak | <2.5GB | 30 | TS 77.8 (terbaik!), BFCL 56.9, IF terbaik | LiquidAI/LFM2.5-2.6B-GGUF ✅ |
| Gemma 4 E4B | Apr-26 | ya (+audio) | ~2.7GB | 14-17 | BFCL mid-80 (native tool token) | unsloth/gemma-4-E4B-it-GGUF ✅ + qat |
| MiniCPM5-1B | Mei-26 | tidak | ~1GB | sangat cepat | 1B SOTA | openbmb/MiniCPM5-1B-GGUF ✅ Q4_K_M |
| Qwen3.8-27B | 14-Agu-26 | ya | besar | - | kuat | ✅ tapi kebesaran utk HP |

Catatan: LFM2.5-2.6B = spesialis agent text (AA Omniscience terbaik, Multi-IF 80),
non-reasoning -> latency rendah. Verdict: Qwen3.5-4B tetap pilihan utama (vision +
tool-calling + drop-in keluarga Qwen); LFM2.5-VL-3B alternatif paling ngebut.
