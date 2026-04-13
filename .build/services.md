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
- DispatchSource.makeFileSystemObjectSource: File watching for vocabulary auto-reload

## Local File Storage
- `~/.voice-dictation/vocabulary.json`: Personal vocabulary (recognition words + replacement mappings)
  - Created automatically with defaults on first run
  - Watched for changes via DispatchSource; auto-reloads without app restart
  - Format: `{"recognitionWords": [...], "replacements": {"trigger": "replacement"}}`
- `~/.voice-dictation/history.json`: Dictation history records
  - Created on first dictation completion
  - Format: JSON array of records with `id`, `rawTranscript`, `cleanedText`, `timestamp` (ISO 8601), `duration`, `audioFilePath` (optional), `status` ("success"|"failed")
  - Records sorted by timestamp descending
  - Written atomically; read at startup by HistoryStore
- `~/.voice-dictation/.env`: API keys (OPENAI_API_KEY)
  - Can be edited from Settings UI; changes require app restart to take effect for pipeline
