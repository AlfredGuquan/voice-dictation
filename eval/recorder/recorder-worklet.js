class PCMRecorder extends AudioWorkletProcessor {
  constructor() {
    super();
    this.recording = false;
    this.port.onmessage = e => {
      if (e.data.type === 'start') this.recording = true;
      else if (e.data.type === 'stop') this.recording = false;
    };
  }
  process(inputs) {
    if (!this.recording) return true;
    const input = inputs[0];
    if (input && input[0] && input[0].length > 0) {
      this.port.postMessage({ type: 'chunk', data: new Float32Array(input[0]) });
    }
    return true;
  }
}
registerProcessor('pcm-recorder', PCMRecorder);
