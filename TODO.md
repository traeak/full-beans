# TODO

## Goal
Convert `fenster_audio.h` (C header) to `src/fenster_audio.zig` using `std.os`/`std.c` platform bindings for macOS, Windows, and Linux, and wire the module into `build.zig`.

## Tasks

### 1. Create `src/fenster_audio.zig` — shared declarations
- [x] Define `FensterAudio` struct with platform-conditional fields (macOS AudioQueue, Windows waveOut, Linux ALSA PCM)
- [x] Define `FensterAudioError` error set
- [x] Declare public API: `init()`, `available()`, `write()`, `close()` (Zig-style naming)
- [x] Define `comptime` constants: `sample_rate` (44100), `buf_size` (8192)

### 2. macOS implementation (`std.c` bindings to AudioToolbox)
- [x] Declare C types/functions from `<AudioToolbox/AudioQueue.h>` via `std.c`
- [x] Implement `init()` — create AudioQueue with float PCM format, allocate buffers, start queue
- [x] Implement callback function for buffer refill (semaphore-based signaling)
- [x] Implement `available()` — check drained semaphore, return remaining space
- [x] Implement `write()` — copy samples into buffer, signal full when complete
- [x] Implement `close()` — stop and dispose AudioQueue

### 3. Windows implementation (`std.c` bindings to mmsystem)
- [x] Declare C types/functions from `<mmsystem.h>` via `std.c`
- [x] Implement `init()` — open waveOut device, prepare and write dual buffers
- [x] Implement `available()` — check WHDR_DONE flag, return buffer size if free
- [x] Implement `write()` — convert float to int16, requeue done buffer
- [x] Implement `close()` — close waveOut device

### 4. Linux implementation (`std.c` bindings to ALSA)
- [x] Declare C function signatures for `snd_pcm_*` family via `std.c`
- [x] Implement `init()` — open PCM device, set float32 params
- [x] Implement `available()` — call `snd_pcm_avail`, recover on error
- [x] Implement `write()` — call `snd_pcm_writei`, recover on error
- [x] Implement `close()` — call `snd_pcm_close`

### 5. Update `build.zig`
- [x] Add `fenster_audio` module to the `full_beans` module imports (re-export from `src/root.zig`)
- [x] Link platform-specific system libraries: `AudioToolbox` (macOS), `winmm` (Windows), `asound` (Linux)
- [x] Link `dispatch` on macOS (for semaphores)

## Notes
- Use `std.c` for C interop (not `@cImport` which is deprecated in 0.16).
- All three platforms must compile; use `comptime` branching on `target.os.tag`.
- Follow TigerStyle: PascalCase types, camelCase functions, explicit error handling, 76-col limit.
- The original C header uses semaphores on macOS (`dispatch_semaphore_t`), dual-buffer ping-pong on Windows, and direct ALSA calls on Linux. Replicate this design in Zig.
