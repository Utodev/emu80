// P/Invoke declarations for e80lib.dll (the emu80 emulation engine as a native
// library, loaded into this process) and a small managed wrapper. C# 5
// compatible (it is built with the .NET Framework's csc).
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace Emu80Host
{
    // Same numbers as the engine's TSpectrumModel
    public enum SpectrumModel { Spectrum16K = 0, Spectrum48K = 1, Spectrum128K = 2, Plus2 = 3, Plus2B = 4, Plus3 = 5, ZXUno = 6, ZXNext = 7 }

    [StructLayout(LayoutKind.Sequential)]
    public struct Emu80State
    {
        public int Running, Paused, BreakKind, Model, PC, FramesLow, FramesHigh, Fps, Attached, TapePlaying;
        public long Frames { get { return ((long)(uint)FramesHigh << 32) | (uint)FramesLow; } }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Emu80Paging
    {
        public int Port7FFD, Port1FFD, Slot0, Slot1, Slot2, Slot3, DivActive, CurrahPaged, UnoConf, UnoMapper;
    }

    public enum Reg { AF = 0, BC, DE, HL, AF2, BC2, DE2, HL2, IX, IY, SP, PC, I, R, IM, IFF1, IFF2 }

    public delegate void FrameCallback(IntPtr user);

    static class Native
    {
        const string Dll = "e80lib.dll";
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_version();
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern IntPtr emu80_create(int model, string romDir);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern void emu80_destroy(IntPtr h);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_last_error(IntPtr h, StringBuilder buf, int size);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_set_model(IntPtr h, int model);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_get_model(IntPtr h);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_set_next_dir(IntPtr h, string dir);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_start(IntPtr h);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_stop(IntPtr h);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_pause(IntPtr h);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_resume(IntPtr h);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_reset(IntPtr h, int hard);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_set_sound(IntPtr h, int enabled);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_set_turbo(IntPtr h, int enabled);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_attach_window(IntPtr h, IntPtr window);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_detach_window(IntPtr h);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_set_display(IntPtr h, int deinterlace, int mono, int scanlines);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_set_frame_callback(IntPtr h, FrameCallback cb, IntPtr user);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_get_frame(IntPtr h, byte[] buf, int size, int scale, out int width, out int height);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_get_reg(IntPtr h, int reg, out int value);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_set_reg(IntPtr h, int reg, int value);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_read_mem(IntPtr h, int addr, byte[] buf, int len);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_write_mem(IntPtr h, int addr, byte[] buf, int len);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_set_rom_writable(IntPtr h, int enabled);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_ram_bank_count(IntPtr h);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_read_ram_bank(IntPtr h, int bank, int offset, byte[] buf, int len);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_write_ram_bank(IntPtr h, int bank, int offset, byte[] buf, int len);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_get_paging(IntPtr h, out Emu80Paging paging);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_write_port(IntPtr h, int port, int value);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_set_slot3_bank(IntPtr h, int bank);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_next_reg_get(IntPtr h, int reg);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_next_reg_set(IntPtr h, int reg, int value);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_set_breakpoint(IntPtr h, int addr, int flags);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_get_breakpoint(IntPtr h, int addr);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_clear_breakpoints(IntPtr h);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_step_into(IntPtr h);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_step_over(IntPtr h);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_run_to(IntPtr h, int addr);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_get_state(IntPtr h, out Emu80State state);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_get_break_reason(IntPtr h, StringBuilder buf, int size);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_load_ram(IntPtr h, int addr, byte[] data, int len);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_load_file(IntPtr h, string fileName);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_key(IntPtr h, int key, int down);
        [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] public static extern int emu80_set_kempston(IntPtr h, int bits);
    }

    // The emulator as a managed object: one engine instance, which outlives
    // the control it is drawn in
    public sealed class Emulator : IDisposable
    {
        IntPtr h;

        public const int BpExec = 1, BpRead = 2, BpWrite = 4;

        public static int ApiVersion { get { return Native.emu80_version(); } }

        public Emulator(SpectrumModel model, string romDir)
        {
            h = Native.emu80_create((int)model, romDir);
            if (h == IntPtr.Zero) throw new InvalidOperationException("emu80_create failed (are the ROMs in " + romDir + "?)");
        }

        void Check(int r, string what)
        {
            if (r < 0) throw new InvalidOperationException(what + " failed (" + r + "): " + LastError);
        }

        public string LastError
        {
            get { StringBuilder sb = new StringBuilder(256); Native.emu80_last_error(h, sb, sb.Capacity); return sb.ToString(); }
        }

        public void Dispose()
        {
            if (h != IntPtr.Zero) { Native.emu80_destroy(h); h = IntPtr.Zero; }
        }

        public SpectrumModel Model
        {
            get { return (SpectrumModel)Native.emu80_get_model(h); }
            set { Check(Native.emu80_set_model(h, (int)value), "set model"); }
        }
        public void SetNextDistribution(string dir) { Check(Native.emu80_set_next_dir(h, dir), "set next dir"); }

        public void Start() { Check(Native.emu80_start(h), "start"); }
        public void Stop() { Check(Native.emu80_stop(h), "stop"); }
        public void Pause() { Check(Native.emu80_pause(h), "pause"); }
        public void Resume() { Check(Native.emu80_resume(h), "resume"); }
        public void Reset(bool hard) { Check(Native.emu80_reset(h, hard ? 1 : 0), "reset"); }
        public bool Sound { set { Native.emu80_set_sound(h, value ? 1 : 0); } }
        public bool Turbo { set { Native.emu80_set_turbo(h, value ? 1 : 0); } }

        // The screen: the host's control (its window handle) is where it is drawn
        public void AttachScreen(IntPtr controlHandle) { Check(Native.emu80_attach_window(h, controlHandle), "attach window"); }
        public void DetachScreen() { Check(Native.emu80_detach_window(h), "detach window"); }
        public void SetDisplay(int deinterlace, bool mono, bool scanlines) { Check(Native.emu80_set_display(h, deinterlace, mono ? 1 : 0, scanlines ? 1 : 0), "display"); }
        public void SetFrameCallback(FrameCallback cb) { Check(Native.emu80_set_frame_callback(h, cb, IntPtr.Zero), "frame callback"); }
        // The latest frame as 32-bit BGRA (top-down), Scale times the 352x288
        public byte[] GetFrame(int scale, out int width, out int height)
        {
            int w, ht;
            int need = Native.emu80_get_frame(h, null, 0, scale, out w, out ht);
            byte[] buf = new byte[need];
            Check(Native.emu80_get_frame(h, buf, buf.Length, scale, out w, out ht), "get frame");
            width = w; height = ht;
            return buf;
        }

        public int GetReg(Reg r) { int v; Check(Native.emu80_get_reg(h, (int)r, out v), "get reg"); return v; }
        public void SetReg(Reg r, int value) { Check(Native.emu80_set_reg(h, (int)r, value), "set reg"); }

        public byte[] ReadMemory(int addr, int len)
        {
            byte[] b = new byte[len];
            Check(Native.emu80_read_mem(h, addr, b, len), "read memory");
            return b;
        }
        public void WriteMemory(int addr, byte[] data) { Check(Native.emu80_write_mem(h, addr, data, data.Length), "write memory"); }
        public bool RomWritable { set { Native.emu80_set_rom_writable(h, value ? 1 : 0); } }
        public int RamBankCount { get { return Native.emu80_ram_bank_count(h); } }
        public byte[] ReadRamBank(int bank, int offset, int len)
        {
            byte[] b = new byte[len];
            Check(Native.emu80_read_ram_bank(h, bank, offset, b, len), "read RAM bank");
            return b;
        }
        public void WriteRamBank(int bank, int offset, byte[] data) { Check(Native.emu80_write_ram_bank(h, bank, offset, data, data.Length), "write RAM bank"); }

        public Emu80Paging Paging { get { Emu80Paging p; Check(Native.emu80_get_paging(h, out p), "paging"); return p; } }
        public void WritePort(int port, int value) { Check(Native.emu80_write_port(h, port, value), "write port"); }
        public void SetSlot3Bank(int bank) { Check(Native.emu80_set_slot3_bank(h, bank), "slot 3 bank"); }
        public int NextRegister(int reg) { return Native.emu80_next_reg_get(h, reg); }
        public void SetNextRegister(int reg, int value) { Check(Native.emu80_next_reg_set(h, reg, value), "next register"); }

        public void SetBreakpoint(int addr, int flags) { Check(Native.emu80_set_breakpoint(h, addr, flags), "breakpoint"); }
        public int GetBreakpoint(int addr) { return Native.emu80_get_breakpoint(h, addr); }
        public void ClearBreakpoints() { Check(Native.emu80_clear_breakpoints(h), "clear breakpoints"); }
        public void StepInto() { Check(Native.emu80_step_into(h), "step"); }
        public void StepOver() { Check(Native.emu80_step_over(h), "step over"); }
        public void RunTo(int addr) { Check(Native.emu80_run_to(h, addr), "run to"); }

        public Emu80State State { get { Emu80State s; Check(Native.emu80_get_state(h, out s), "state"); return s; } }
        public string BreakReason
        {
            get { StringBuilder sb = new StringBuilder(256); Native.emu80_get_break_reason(h, sb, sb.Capacity); return sb.ToString(); }
        }

        public void LoadRam(int addr, byte[] data) { Check(Native.emu80_load_ram(h, addr, data, data.Length), "load RAM"); }
        public void LoadFile(string path) { Check(Native.emu80_load_file(h, path), "load file"); }

        // The host tells the keys: Key is row * 5 + bit of the Spectrum's keyboard (0 = CAPS SHIFT)
        public void Key(int key, bool down) { Native.emu80_key(h, key, down ? 1 : 0); }
        public void Kempston(int bits) { Native.emu80_set_kempston(h, bits); }
    }
}
