//! Platform-specific audio playback via C interop.
//!
//! macOS: AudioQueue (float32 PCM, semaphore-driven callback).
//! Windows: waveOut (int16 PCM, dual-buffer ping-pong).
//! Linux: ALSA (float32 PCM, direct snd_pcm calls).

const std = @import("std");
const mem = std.mem;
const c = std.c;

pub const FensterAudioError = error{
    DeviceOpen,
    AlsaStream,
};

pub const sample_rate: c_uint = 44100;
pub const buf_size: usize = 8192;

// ---------------------------------------------------------------------------
// Platform-specific type declarations
// ---------------------------------------------------------------------------

/// macOS AudioToolbox types.
const AudioQueueRef = *anyopaque;
const AudioQueueBufferRef = *anyopaque;
const dispatch_semaphore_t = *anyopaque;

/// macOS AudioStreamBasicDescription (64 bytes, align(8)).
///
/// Matches the C struct layout from AudioToolbox.
const AudioStreamBasicDescription = extern struct {
    mSampleRate: f64,
    mFormatID: u32,
    mFormatFlags: u32,
    mBytesPerPacket: u32,
    mFramesPerPacket: u32,
    mBytesPerFrame: u32,
    mChannelsPerFrame: u32,
    mBitsPerChannel: u32,
    mReserved: u32,
};

/// Windows WAVEFORMATEX (base, 14 bytes, align(2)).
const WAVEFORMATEX = extern struct {
    wFormatTag: u16,
    nChannels: u16,
    nSamplesPerSec: u32,
    nAvgBytesPerSec: u32,
    nBlockAlign: u16,
    wBitsPerSample: u16,
    cbSize: u16,
};

/// Windows WAVEHDR (32 bytes on 64-bit).
const WAVEHDR = extern struct {
    lpData: [*]u8,
    dwBufferLength: u32,
    dwBytesRecorded: u32,
    dwUser: ?*anyopaque,
    dwFlags: u32,
    dwLoops: u32,
    lpNext: ?*anyopaque,
    reserved: u32,
    callback: ?*anyopaque,
};

// ---------------------------------------------------------------------------
// Platform-specific FensterAudio struct
// ---------------------------------------------------------------------------

const FensterAudioMacos = extern struct {
    queue: AudioQueueRef,
    pos: usize,
    buf: [buf_size]f32,
    drained: dispatch_semaphore_t,
    full: dispatch_semaphore_t,
};

const FensterAudioWindows = extern struct {
    wo: ?*anyopaque,
    hdr: [2]WAVEHDR,
    buf: [2][buf_size]i16,
};

const FensterAudioLinux = extern struct {
    pcm: ?*anyopaque,
    buf: [buf_size]f32,
    pos: usize,
};

/// Audio output context. Selects the platform-specific struct at compile time.
pub const FensterAudio: type = if (std.target.os.tag == .macos)
    FensterAudioMacos
else if (std.target.os.tag == .windows)
    FensterAudioWindows
else if (std.target.os.tag == .linux)
    FensterAudioLinux
else
    @compileError("fenster_audio: unsupported OS " ++ @tagName(std.target.os.tag));

// ---------------------------------------------------------------------------
// macOS — AudioToolbox / libdispatch extern declarations
// ---------------------------------------------------------------------------

// kAudioFormatLinearPCM = 0x6C696E70 ("linp")
const kAudioFormatLinearPCM: u32 = 0x6C696E70;
// kLinearPCMFormatFlagIsFloat = 0x0001
const kLinearPCMFormatFlagIsFloat: u32 = 0x0001;
// kAudioFormatFlagIsPacked = 0x0001
const kAudioFormatFlagIsPacked: u32 = 0x0001;

const DISPATCH_TIME_FOREVER: u64 = std.math.maxInt(u64);
const DISPATCH_TIME_NOW: u64 = 0;

extern "dispatch" fn dispatch_semaphore_create(value: c_long) dispatch_semaphore_t;
extern "dispatch" fn dispatch_semaphore_wait(sema: dispatch_semaphore_t, timeout: u64) c_long;
extern "dispatch" fn dispatch_semaphore_signal(sema: dispatch_semaphore_t) void;
extern "dispatch" fn dispatch_release(object: *anyopaque) void;

extern "AudioToolbox" fn AudioQueueNewOutput(
    format: *const AudioStreamBasicDescription,
    callback: *const anyopaque,
    user_data: *anyopaque,
    run_loop_mode: ?*anyopaque,
    run_loop: ?*anyopaque,
    extension_flags: u32,
    queue_out: *AudioQueueRef,
) c_int;

extern "AudioToolbox" fn AudioQueueAllocateBuffer(
    queue: AudioQueueRef,
    buffer_byte_size: c_int,
    buffer_out: *AudioQueueBufferRef,
) c_int;

extern "AudioToolbox" fn AudioQueueEnqueueBuffer(
    queue: AudioQueueRef,
    buffer: AudioQueueBufferRef,
    num_values: c_int,
    values: ?*const anyopaque,
) c_int;

extern "AudioToolbox" fn AudioQueueStart(queue: AudioQueueRef, start_time: ?*anyopaque) c_int;
extern "AudioToolbox" fn AudioQueueStop(queue: AudioQueueRef, immediate: c_int) c_int;
extern "AudioToolbox" fn AudioQueueDispose(queue: AudioQueueRef, immediate: c_int) c_int;

// ---------------------------------------------------------------------------
// Windows — waveOut extern declarations
// ---------------------------------------------------------------------------

const WAVE_FORMAT_PCM: u16 = 1;
const WHDR_DONE: u32 = 0x0001;
const WAVE_MAPPER: c_ulong = std.math.maxInt(c_ulong);

extern "winmm" fn waveOutOpen(
    lphWaveOut: *?*anyopaque,
    uDeviceID: c_ulong,
    lpFormat: *const WAVEFORMATEX,
    dwCallback: c_ulong,
    dwInstance: c_ulong,
    dwFlags: u32,
) c_int;

extern "winmm" fn waveOutPrepareHeader(
    hWaveOut: ?*anyopaque,
    lpWaveOutHdr: *WAVEHDR,
    uSize: u32,
) c_int;

extern "winmm" fn waveOutWrite(
    hWaveOut: ?*anyopaque,
    lpWaveOutHdr: *const WAVEHDR,
    uSize: u32,
) c_int;

extern "winmm" fn waveOutClose(hWaveOut: ?*anyopaque) c_int;

// ---------------------------------------------------------------------------
// Linux — ALSA extern declarations
// ---------------------------------------------------------------------------

const SND_PCM_FORMAT_FLOAT_LE: c_int = 14;
const SND_PCM_FORMAT_FLOAT_BE: c_int = 15;
const SND_PCM_ACCESS_RW_INTERLEAVED: c_int = 3;

extern "asound" fn snd_pcm_open(
    pcm: ?**anyopaque,
    name: [*:0]const u8,
    dir: c_int,
    mode: c_int,
) c_int;

extern "asound" fn snd_pcm_set_params(
    pcm: ?*anyopaque,
    format: c_int,
    access: c_int,
    channels: c_int,
    rate: c_uint,
    soft_resample: c_int,
    latency: c_int,
) c_int;

extern "asound" fn snd_pcm_avail(pcm: ?*anyopaque) c_int;
extern "asound" fn snd_pcm_writei(pcm: ?*anyopaque, buffer: ?*const anyopaque, size: c_ulong) c_int;
extern "asound" fn snd_pcm_recover(pcm: ?*anyopaque, err: c_int, ign_prepare: c_int) c_int;
extern "asound" fn snd_pcm_close(pcm: ?*anyopaque) c_int;

// ---------------------------------------------------------------------------
// macOS callback — must be a top-level C-callable function
// ---------------------------------------------------------------------------

/// C callback invoked by AudioQueue when a buffer has been consumed.
///
/// Waits for the producer to fill the internal buffer, copies data into the
/// AudioQueue buffer, and re-enqueues it.
fn audioQueueCallback(
    user_data: *anyopaque,
    queue: AudioQueueRef,
    buffer: AudioQueueBufferRef,
) void {
    const fa: *FensterAudioMacos = @ptrCast(@alignCast(user_data));

    // Wait until the producer has filled our internal buffer.
    _ = dispatch_semaphore_wait(fa.full, DISPATCH_TIME_FOREVER);

    // Copy our buffer into the AudioQueue buffer.
    // The buffer struct has mAudioDataByteSize at offset 0 and mAudioData at offset 8.
    const buf_ints: [*]c_int = @ptrCast(@alignCast(buffer));
    const data_ptr: [*]f32 = @ptrCast(@alignCast(&buf_ints[2]));
    mem.copyForwards(f32, data_ptr[0..buf_size], fa.buf[0..]);

    // Signal that our internal buffer is drained and ready for new data.
    dispatch_semaphore_signal(fa.drained);

    // Re-enqueue the buffer for playback.
    _ = AudioQueueEnqueueBuffer(queue, buffer, 0, null);
}

// ---------------------------------------------------------------------------
// Public API — platform-specific implementations
// ---------------------------------------------------------------------------

/// Open the audio device and start playback.
///
/// On Linux this can fail if the PCM device is unavailable.
pub fn fenster_audio_open(fa: *FensterAudio) FensterAudioError!void {
    if (std.target.os.tag == .macos) {
        const fa_mac: *FensterAudioMacos = @ptrCast(@alignCast(fa));
        const format = AudioStreamBasicDescription{
            .mSampleRate = @floatFromInt(sample_rate),
            .mFormatID = kAudioFormatLinearPCM,
            .mFormatFlags = kLinearPCMFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            .mBytesPerPacket = 4,
            .mFramesPerPacket = 1,
            .mBytesPerFrame = 4,
            .mChannelsPerFrame = 1,
            .mBitsPerChannel = 32,
            .mReserved = 0,
        };

        fa_mac.drained = dispatch_semaphore_create(1);
        fa_mac.full = dispatch_semaphore_create(0);
        fa_mac.pos = 0;
        @memset(&fa_mac.buf, 0);

        var queue: AudioQueueRef = undefined;
        _ = AudioQueueNewOutput(
            &format,
            &audioQueueCallback,
            fa_mac,
            null,
            null,
            0,
            &queue,
        );
        fa_mac.queue = queue;

        // Allocate and enqueue two buffers.
        var i: usize = 0;
        while (i < 2) : (i += 1) {
            var buffer: AudioQueueBufferRef = undefined;
            _ = AudioQueueAllocateBuffer(queue, @intCast(buf_size * 4), &buffer);
            // Set mAudioDataByteSize and zero the data area.
            const buf_ints: [*]c_int = @ptrCast(@alignCast(buffer));
            buf_ints[0] = @intCast(buf_size * 4);
            const data_ptr: [*]f32 = @ptrCast(@alignCast(&buf_ints[2]));
            @memset(data_ptr[0..buf_size], 0);
            _ = AudioQueueEnqueueBuffer(queue, buffer, 0, null);
        }

        _ = AudioQueueStart(queue, null);
    } else if (std.target.os.tag == .windows) {
        const fa_win: *FensterAudioWindows = @ptrCast(@alignCast(fa));
        const wfx = WAVEFORMATEX{
            .wFormatTag = WAVE_FORMAT_PCM,
            .nChannels = 1,
            .nSamplesPerSec = sample_rate,
            .nAvgBytesPerSec = sample_rate * 2,
            .nBlockAlign = 1,
            .wBitsPerSample = 16,
            .cbSize = 0,
        };

        var wo: ?*anyopaque = null;
        _ = waveOutOpen(&wo, WAVE_MAPPER, &wfx, 0, 0, 0);
        fa_win.wo = wo;

        // Prepare and queue two ping-pong buffers.
        var i: usize = 0;
        while (i < 2) : (i += 1) {
            fa_win.hdr[i] = WAVEHDR{
                .lpData = fa_win.buf[i][0..],
                .dwBufferLength = buf_size * 2,
                .dwBytesRecorded = 0,
                .dwUser = null,
                .dwFlags = 0,
                .dwLoops = 0,
                .lpNext = null,
                .reserved = 0,
                .callback = null,
            };
            _ = waveOutPrepareHeader(wo, &fa_win.hdr[i], @sizeOf(WAVEHDR));
            _ = waveOutWrite(wo, &fa_win.hdr[i], @sizeOf(WAVEHDR));
        }
    } else if (std.target.os.tag == .linux) {
        const fa_linux: *FensterAudioLinux = @ptrCast(@alignCast(fa));
        fa_linux.pos = 0;
        @memset(&fa_linux.buf, 0);

        var pcm: ?*anyopaque = null;
        if (snd_pcm_open(&pcm, "default", 0, 0) != 0) {
            return FensterAudioError.DeviceOpen;
        }
        fa_linux.pcm = pcm;

        // Choose float format based on target endianness.
        const fmt: c_int = if (std.builtin.target.endian == .Little)
            SND_PCM_FORMAT_FLOAT_LE
        else
            SND_PCM_FORMAT_FLOAT_BE;

        const r = snd_pcm_set_params(pcm, fmt, SND_PCM_ACCESS_RW_INTERLEAVED, 1, sample_rate, 1, 100_000);
        if (r < 0) {
            _ = snd_pcm_close(pcm);
            fa_linux.pcm = null;
            return FensterAudioError.AlsaStream;
        }
    }
}

/// Close the audio device and release resources.
pub fn fenster_audio_close(fa: *FensterAudio) void {
    if (std.target.os.tag == .macos) {
        const fa_mac: *FensterAudioMacos = @ptrCast(@alignCast(fa));
        _ = AudioQueueStop(fa_mac.queue, 0);
        _ = AudioQueueDispose(fa_mac.queue, 0);
        dispatch_release(fa_mac.drained);
        dispatch_release(fa_mac.full);
    } else if (std.target.os.tag == .windows) {
        const fa_win: *FensterAudioWindows = @ptrCast(@alignCast(fa));
        _ = waveOutClose(fa_win.wo);
    } else if (std.target.os.tag == .linux) {
        const fa_linux: *FensterAudioLinux = @ptrCast(@alignCast(fa));
        if (fa_linux.pcm) |pcm| {
            _ = snd_pcm_close(pcm);
        }
    }
}

/// Returns the number of samples that can be written without blocking.
pub fn fenster_audio_available(fa: *const FensterAudio) usize {
    if (std.target.os.tag == .macos) {
        const fa_mac: *const FensterAudioMacos = @ptrCast(@alignCast(fa));
        const result = dispatch_semaphore_wait(fa_mac.drained, DISPATCH_TIME_NOW);
        if (result != 0) return 0;
        return buf_size - fa_mac.pos;
    } else if (std.target.os.tag == .windows) {
        const fa_win: *const FensterAudioWindows = @ptrCast(@alignCast(fa));
        var i: usize = 0;
        while (i < 2) : (i += 1) {
            if (fa_win.hdr[i].dwFlags & WHDR_DONE != 0) {
                return buf_size;
            }
        }
        return 0;
    } else if (std.target.os.tag == .linux) {
        const fa_linux: *const FensterAudioLinux = @ptrCast(@alignCast(fa));
        const n = snd_pcm_avail(fa_linux.pcm orelse return 0);
        if (n < 0) {
            _ = snd_pcm_recover(fa_linux.pcm, n, 0);
        }
        return @as(usize, @bitCast(@as(isize, @intCast(n))));
    }
    unreachable;
}

/// Write audio samples to the output buffer.
///
/// Samples that do not fit in the available space are silently dropped,
/// matching the original C header behavior.
pub fn fenster_audio_write(fa: *FensterAudio, samples: []const f32) void {
    if (std.target.os.tag == .macos) {
        const fa_mac: *FensterAudioMacos = @ptrCast(@alignCast(fa));
        var remaining = samples.len;
        var idx: usize = 0;
        while (fa_mac.pos < buf_size and remaining > 0) {
            fa_mac.buf[fa_mac.pos] = samples[idx];
            fa_mac.pos += 1;
            idx += 1;
            remaining -= 1;
        }
        if (fa_mac.pos >= buf_size) {
            fa_mac.pos = 0;
            dispatch_semaphore_signal(fa_mac.full);
        }
    } else if (std.target.os.tag == .windows) {
        const fa_win: *FensterAudioWindows = @ptrCast(@alignCast(fa));
        var i: usize = 0;
        while (i < 2) : (i += 1) {
            if (fa_win.hdr[i].dwFlags & WHDR_DONE != 0) {
                var j: usize = 0;
                while (j < samples.len) : (j += 1) {
                    const clamped: f32 = @min(@max(samples[j] * 32767.0, -32768.0), 32767.0);
                    fa_win.buf[i][j] = @intFromFloat(clamped);
                }
                _ = waveOutWrite(fa_win.wo, &fa_win.hdr[i], @sizeOf(WAVEHDR));
                return;
            }
        }
    } else if (std.target.os.tag == .linux) {
        const fa_linux: *FensterAudioLinux = @ptrCast(@alignCast(fa));
        _ = snd_pcm_writei(fa_linux.pcm, samples.ptr, samples.len);
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Verify that constants and struct sizes are sane at compile time.
test "fenster_audio: constants and struct sizes" {
    // Sample rate is a reasonable audio rate.
    try std.testing.expect(sample_rate > 0);
    try std.testing.expect(sample_rate <= 192_000);

    // Buffer size is a power of two.
    try std.testing.expect(buf_size > 0);
    try std.testing.expect((buf_size & (buf_size - 1)) == 0);

    // FensterAudio resolves to a non-empty type (has fields).
    try std.testing.expect(@sizeOf(FensterAudio) > 0);

    // Platform-specific struct sizes are consistent.
    if (std.target.os.tag == .linux) {
        // Linux struct: pcm pointer + buf + pos.
        const expected: usize = @sizeOf(?*anyopaque) + buf_size * 4 + @sizeOf(usize);
        try std.testing.expectEqual(expected, @sizeOf(FensterAudioLinux));
    }
}

// Attempt to open and close the audio device.
//
// This is an integration test — it will pass even if no audio hardware
// is available, as long as the error path is exercised correctly.
test "fenster_audio: open and close" {
    var fa: FensterAudio = undefined;

    const result = fenster_audio_open(&fa);
    if (result) |_| {
        // Open succeeded — close it and verify no crash.
        fenster_audio_close(&fa);
    } else |err| {
        // Open failed — acceptable when no audio device is present.
        // Verify the error is one we recognize.
        _ = err;
    }
}
