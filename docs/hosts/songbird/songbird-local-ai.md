# Songbird local AI

The RTX 5080 runs open-weight models on songbird, so chat, coding side work, speech, images, and document conversion stay on the host.

- [songbird-runbook-local-ai.md](songbird-runbook-local-ai.md)
- [songbird-troubleshooting-local-ai.md](songbird-troubleshooting-local-ai.md)

## How models are served

- The `llama-cpp` system service runs llama.cpp's `llama-server` with CUDA from [llama-cpp.nix](../../../modules/apps/llama-cpp.nix), so it serves without a login and without `/data`.
- In router mode it keeps one model loaded, in a child process, and swaps models when a request names another preset entry from [services.nix](../../../modules/hosts/songbird/services.nix).
- Models download from Hugging Face on first load into `/var/cache/llama-cpp` on disk A.
- One port serves the OpenAI and Anthropic APIs and the web UI to loopback, the LAN, and the Mesh; every request except health checks and web UI assets needs the sops API key.
- A key holder can also download any Hugging Face model into the cache, or delete a cached one, through the router's `/models` API.
- Child processes listen on loopback without a key, so any process in the host network namespace reaches the loaded model.

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
- The Qwen3.5 9B comparison pairs Magnitude with DFlash drafting against llama.cpp without drafting.
  DFlash proposes token blocks for the main model to check.
- The GPU draws about 300 W while decoding, up to 365 W during prefill, and 42 W idle.

## Model roles

Each role names a section of the models preset in [services.nix](../../../modules/hosts/songbird/services.nix), measured with llama.cpp 0.7.0 on CUDA.

- `gemma-4-26b-a4b` is the default, as the only preset that passes every client, tool-call, and vision check.
- `lfm2.5-24b-a2b` decodes 273 tokens per second at a 1.9k-token prompt and 230 at 31k, text only; its weaker tool picks suit bulk work, not agents.
- `mimo-v2.6-9b` is the light vision and agent model, but it ignores a required tool choice in 5 of 9 requests, so paperless avoids it.
- `qwen3.8-27b-gsq-mtp`'s chat template rejects the non-leading system messages that Claude Code and Codex send.
  Claude Code passed its client checks through a proxy that folds them into the first; the nixpkgs fork's CUDA llama-cpp folds them in the server, meant to cover both clients.
- `minicpm5-2b` is the small text-only preset, and `minicpm5-2b-dspark` adds DSpark drafting, which decodes 1.5 times as fast.

## What it enables

- A private assistant: chat, image questions, and document questions with Qwen3.8 27B or Gemma 4, also served to the iPhone over the Mesh.
- Side work for Claude Code and Codex: commit messages, summaries, log triage, classification, and anything whose data must stay on the host.
- Local code search and next-edit completion with small embedding and completion models.
- Speech: push-to-talk dictation, meeting transcripts with speaker labels, and text to speech with voice cloning.
- Images and video: image generation and editing, and short 720p clips with sound.
- Documents: scans and PDFs converted to Markdown with layout and tables.
- Fine-tuning: LoRA adapters for 4B-class language models and for image models.

## Limits

- Long multi-file engineering stays with hosted frontier models, which lead every model that fits by a wide margin on the Artificial Analysis Intelligence Index.
- One engine owns the GPU at a time: language, image, and speech models share the same 16 GB, and a second engine evicts or starves the first.
- Models whose 4-bit file exceeds about 40 GB, such as GLM-5.3, Kimi K3, and Qwen3.5 122B-A10B, fit in neither VRAM nor the RAM the desktop leaves free.
- The PCIe 4.0 link in [songbird-hardware.md](songbird-hardware.md) slows prefill whenever weights stream from RAM.
- The 37xx NPU runs small OpenVINO models only, so language models stay on the RTX 5080.
- Model files take up to 25 GB each on disk A, plus up to 1.4 GB per drafter or vision projector.

## Sources

- Artificial Analysis model leaderboard: <https://artificialanalysis.ai/leaderboards/models>
