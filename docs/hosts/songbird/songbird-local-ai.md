# Songbird local AI

The RTX 5080 and the Arrow Lake iGPU run open-weight models on songbird, so chat, coding side work, speech, images, and document conversion stay on the host.

- [songbird-runbook-local-ai.md](songbird-runbook-local-ai.md)
- [songbird-runbook-paperless.md](songbird-runbook-paperless.md)
- [songbird-troubleshooting-local-ai.md](songbird-troubleshooting-local-ai.md)

## How models are served

- The `llama-cpp` system service runs llama.cpp's `llama-server` from [llama-cpp.nix](../../../modules/apps/llama-cpp.nix), so it serves without a login and without `/data`.
- `llama-server` builds from llama.cpp master through the `llama-cpp` flake input, so updating that input brings in models upstream merged since the last update.
- In router mode it keeps one model loaded, in a child process, and swaps models when a request names another preset entry from [services.nix](../../../modules/hosts/songbird/services.nix).
- Models download from Hugging Face on first load into `/var/cache/llama-cpp` on disk A.
- One port serves the OpenAI and Anthropic APIs and the web UI to loopback, the LAN, and the Mesh; every request except health checks and web UI assets needs the sops API key.
- A key holder can also download any Hugging Face model into the cache, or delete a cached one, through the router's `/models` API.
- Child processes listen on loopback without a key, so any process in the host network namespace reaches the loaded model.
- A second service, `llama-cpp-embed`, serves one pinned embedding model on the CPU to loopback, so paperless embeddings never evict the router's model.
- paperless-ngx sends its suggestions and document chat to the router's default model with a key of its own, so it never makes the router swap models: [paperless.nix](../../../modules/apps/paperless.nix).

## Speech-to-text on the iGPU

- Two more services transcribe speech on the iGPU through Vulkan, on loopback with the router's keys, so speech-to-text never touches the RTX 5080: [llama-cpp.nix](../../../modules/apps/llama-cpp.nix).
- Recordings and files go to `llama-cpp-transcribe`, which serves Qwen3-ASR 1.7B over the OpenAI-style `/v1/audio/transcriptions` and decodes WAV, MP3, and FLAC.
- Live microphone audio goes to `llama-cpp-dictate`, which serves LFM3-Audio 2B over the `/v1/realtime?intent=transcription` WebSocket, English only.
  LFM3-Audio loops or drops words on long files sent in one request, so files stay with Qwen3-ASR.
- Together they hold about 10 GiB of shared memory; `llama-cpp-transcribe` frees its 6.6 GiB after an idle period, and the next request waits for the reload.
- A transcription request holds about 16 tokens per second of audio, so one request fits about 34 minutes, and concurrent requests share that context.
- Qwen3-ASR returns `text` as `language <Name><asr_text>` followed by the transcript, so clients strip everything through `<asr_text>`.
- Qwen3-ASR detects the spoken language, so the `language` field is optional; a `prompt` field replaces the transcription instruction, so clients leave it unset.
- A live client sends the `Authorization` header with the WebSocket upgrade, then `input_audio_buffer.append` events of base64 PCM16 mono at the rate `session.created` reports.
  It ends the input with `input_audio_buffer.commit` and `"final": true`, and reads `conversation.item.input_audio_transcription.delta` and `.completed` events.

## How a model fits

- A model is a file of weights, and generating one token reads every active weight once, so memory bandwidth sets the decode speed.
- VRAM is the fast tier: 16 GB of GDDR7 at about 960 GB/s, of which the X11 desktop holds about 1.2 GB.
- System RAM is the slow tier: llama.cpp reads it at about 65 GB/s, so a 7 GB dense model decodes near 10 tokens per second.
- Quantization stores each weight in 3 to 5 bits instead of 16; a 4-bit file is about a quarter of the original size and keeps most of the quality.
- The KV cache holds the conversation, grows with the context length, and shares VRAM with the weights; a `q8_0` cache takes half the space of the default.
- A mixture-of-experts (MoE) model activates only a few experts per token, 3 to 4 billion parameters out of 26 to 35 billion here.
  Its idle experts can sit in RAM at a moderate speed cost.
- Prompt processing (prefill) reads the input in parallel at 40 to 60 times the plain decode rate, so a long prompt costs seconds.

## Speeds

Single-user tokens per second on songbird with llama.cpp 0.6.0 (build 11429), using CUDA for GPU placements unless the row names Magnitude.
People read about 5 tokens per second, so anything above 40 feels instant.

| Model and quantization          | Placement            | Decode | Prefill |
| ------------------------------- | -------------------- | -----: | ------: |
| Gemma 4 E4B, QAT Q4             | GPU                  |    198 |  11,800 |
| Qwen3.5 9B, UD-Q5_K_XL          | GPU                  |    125 |   6,500 |
| Qwen3.5 9B, Q5, Magnitude       | GPU, DFlash drafting |    195 |   5,300 |
| Qwen3.5 9B, UD-Q5_K_XL          | CPU only             |     10 |     n/a |
| Gemma 4 26B-A4B, UD-IQ4_XS      | GPU                  |    176 |   7,500 |
| Gemma 4 26B-A4B, 32K in context | GPU, `q8_0` cache    |    123 |   5,000 |

- Vulkan builds decode about a quarter slower than CUDA on Qwen3.5 9B and match it on Gemma 4 E4B.
- On build 11960, EmbeddingGemma 2 (Q8_0) embeds 512-token inputs at 2,440 tokens per second on the iGPU and 1,160 on 8 CPU threads.
  At 2048-token inputs both run near 1,330.
- On build 11960, Qwen3-ASR 1.7B (Q8_0) on the iGPU transcribes one request at 3.8 times real time, a median 2.2 s per clip of under 40 s, using a third of a CPU core.
  It transcribes recordings of 2.5 to 5 minutes in one request at 4.5 times real time.
- Over `/v1/realtime`, LFM3-Audio 2B (Q8_0) on the iGPU shows the first words 1.2 to 2.2 s into speech and the final text within 0.7 s of its end.
  Text arrives in bursts about once a second.
- Vulkan flash attention halves the iGPU's embedding speed at 512 tokens and costs more at 2048, since Mesa ANV exposes no matrix cores.
- The Qwen3.5 9B comparison pairs Magnitude with DFlash drafting against llama.cpp without drafting.
  DFlash proposes token blocks for the main model to check.
- The GPU draws about 300 W while decoding, up to 365 W during prefill, and 42 W idle.

## Model roles

Each role names a section of the models preset in [services.nix](../../../modules/hosts/songbird/services.nix), measured with llama.cpp 0.7.0 on CUDA.

- `qwen3.8-27b-gsq-mtp` is the default: paperless suggestions pass with it and map existing tags that Gemma 4 leaves as new names.
- `gemma-4-26b-a4b` is the only preset that passes every client, tool-call, and vision check, and suggests about 2.5 times as fast as the default.
- `lfm2.5-24b-a2b` decodes 273 tokens per second at a 1.9k-token prompt and 230 at 31k, text only; its weaker tool picks suit bulk work, not agents.
- `ornith-1.5-9b` is the light vision, coding, and agent model; MTP drafting decodes it at 130 tokens per second on short prompts.
  It ignores a required tool choice in 5 of 10 requests, so paperless avoids it.
  A vendored chat template renders the system messages its GGUF template drops after the first two.
- `qwen3.8-27b-gsq-mtp`'s chat template rejects system messages after the first, which agent clients commonly send.
  It passed the client checks only through a proxy that folds them into the first.
- `lfm3-1.7b` is the small text-only helper for tool calls, JSON extraction, and summaries, passing 51 of 60 helper checks on build 11942.
  It decodes 288 tokens per second, prefills 23.6k per second at a 55k-token prompt, and takes 4.4 GB of VRAM at its 256k context.
  Its paperless dates and correspondents are unreliable, so paperless avoids it.

## What it enables

- A private assistant: chat, image questions, and document questions with Qwen3.8 27B or Gemma 4, also served to the iPhone over the Mesh.
- Side work for any agent or API client: commit messages, summaries, log triage, classification, and anything whose data must stay on the host.
- Local code search and next-edit completion with small embedding and completion models.
- Speech: push-to-talk dictation, meeting transcripts with speaker labels, and text to speech with voice cloning.
- Images and video: image generation and editing, and short 720p clips with sound.
- Documents: scans and PDFs converted to Markdown with layout and tables.
- Fine-tuning: LoRA adapters for 4B-class language models and for image models.

## Limits

- Long multi-file engineering stays with hosted frontier models, which lead every model that fits by a wide margin on the Artificial Analysis Intelligence Index.
- Claude Code and Codex run only against hosted models; local agent work runs in qwen-code, which is built for OpenAI-compatible servers.
- One engine owns the RTX 5080 at a time: language, image, and speech generation models share the same 16 GB, and a second engine evicts or starves the first.
- Models whose 4-bit file exceeds about 40 GB, such as GLM-5.3, Kimi K3, and Qwen3.5 122B-A10B, fit in neither VRAM nor the RAM the desktop leaves free.
- The 37xx NPU runs small OpenVINO models only, so language models stay on the RTX 5080.
- Model files take up to 25 GB each on disk A, plus up to 1.4 GB per drafter or vision projector.
- `ornith-1.5-9b` ignores `tool_choice = required`, which paperless AI suggestions need, so it cannot replace the default model while paperless uses it.

## Sources

- Artificial Analysis model leaderboard: <https://artificialanalysis.ai/leaderboards/models>
