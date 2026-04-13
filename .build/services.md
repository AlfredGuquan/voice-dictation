# External Services

## OpenAI Whisper API
- Endpoint: `POST https://api.openai.com/v1/audio/transcriptions`
- Model: `whisper-1`
- Auth: Bearer token from `OPENAI_API_KEY`
- Input: multipart/form-data with WAV file (48kHz Int16 PCM), `language=zh`
- Output: JSON with `text` field
- Timeout: 60s
- Cost: ~$0.006/min of audio

## OpenAI Chat Completions (GPT-4o-mini)
- Endpoint: `POST https://api.openai.com/v1/chat/completions`
- Model: `gpt-4o-mini`, temperature 0.3
- Auth: Bearer token from `OPENAI_API_KEY`
- Purpose: Clean up raw transcription (remove filler words, repeated phrases)
- Cost: ~0.0002 CNY/request

## Environment Variables
- `OPENAI_API_KEY`: Required. Loaded from `.env` in project root or `~/.voice-dictation/.env`
- `GEMINI_API_KEY`: Present in .env but unused currently

## macOS System APIs Used
- Accessibility API: CGEvent tap for global hotkey, AXUIElement for focus detection
- AVAudioEngine: Microphone capture
- NSPasteboard: Clipboard read/write for text injection
- CGEvent: Keyboard simulation (Cmd+V paste)
- osascript: System notifications (display notification)
