// A C# (WinForms) host for the pzx library: the Spectrum's screen is drawn by
// the engine, inside a panel of this form (no window of pzx's own; the library
// is loaded into this process). The buttons show the rest of the API:
// pause, registers, memory, paging, breakpoints, destroying and creating the
// panel without losing the machine.
//
//   PzxHostDemo.exe [romsFolder]            the demo window
//   PzxHostDemo.exe --selftest [romsFolder] the same, running a script of checks
//                                           (screenshots and selftest.log next
//                                           to the exe; exit code 0 if all pass)
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace PzxHost
{
    // A panel the engine draws in: it leaves the painting to it
    class ScreenPanel : Panel
    {
        public ScreenPanel()
        {
            SetStyle(ControlStyles.Opaque | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
            BackColor = Color.Black;
        }
        protected override void OnPaintBackground(PaintEventArgs e) { }
        protected override void OnPaint(PaintEventArgs e) { }
    }

    class MainForm : Form
    {
        static readonly string[] KeyRows = {
            "\0ZXCV", "ASDFG", "QWERT", "12345", "09876", "POIUY", "\nLKJH", " \0MNB" };

        Emulator emu;
        ScreenPanel screen;
        readonly Panel host = new Panel();
        readonly Label regs = new Label();
        readonly Label status = new Label();
        readonly Timer timer = new Timer();
        readonly string romDir;
        readonly bool selfTest;
        readonly StringBuilder log = new StringBuilder();
        int failures;
        Button pauseButton;
        FrameCallback frameCallback;
        long callbackFrames;

        public MainForm(string romDir, bool selfTest)
        {
            this.romDir = romDir;
            this.selfTest = selfTest;
            Text = "pzx library in a C# host";
            ClientSize = new Size(1040, 640);
            KeyPreview = true;

            Panel tools = new Panel();
            tools.Dock = DockStyle.Left;
            tools.Width = 250;
            Controls.Add(tools);
            host.Dock = DockStyle.Fill;
            host.BackColor = Color.FromArgb(40, 40, 40);
            host.Padding = new Padding(8);
            Controls.Add(host);
            host.BringToFront();

            int y = 8;
            pauseButton = AddButton(tools, "Pause", ref y, delegate { TogglePause(); });
            AddButton(tools, "Reset", ref y, delegate { emu.Reset(true); });
            AddButton(tools, "Step into (paused)", ref y, delegate { emu.StepInto(); Refresh_(); });
            AddButton(tools, "Load test program at 8000", ref y, delegate { LoadTestProgram(); });
            AddButton(tools, "Run it (PC = 8000)", ref y, delegate { emu.SetReg(Reg.PC, 0x8000); });
            AddButton(tools, "Page bank 0 at C000", ref y, delegate { emu.WritePort(0x7FFD, 0x10); });
            AddButton(tools, "Page bank 1 at C000", ref y, delegate { emu.WritePort(0x7FFD, 0x11); });
            AddButton(tools, "HL = 1234", ref y, delegate { emu.SetReg(Reg.HL, 0x1234); Refresh_(); });
            AddButton(tools, "Breakpoint at 8001", ref y, delegate { emu.SetBreakpoint(0x8001, Emulator.BpExec); });
            AddButton(tools, "Clear breakpoints", ref y, delegate { emu.ClearBreakpoints(); });
            AddButton(tools, "Destroy the panel", ref y, delegate { DestroyPanel(); });
            AddButton(tools, "Create the panel", ref y, delegate { CreatePanel(); });
            AddButton(tools, "Weave deinterlace", ref y, delegate { emu.SetDisplay(2, false, false); });
            AddButton(tools, "Progressive", ref y, delegate { emu.SetDisplay(0, false, false); });
            regs.Left = 8; regs.Top = y + 4; regs.Width = 230; regs.Height = 150;
            regs.Font = new Font(FontFamily.GenericMonospace, 9f);
            tools.Controls.Add(regs);
            status.Dock = DockStyle.Bottom; status.Height = 22;
            status.Font = new Font(FontFamily.GenericMonospace, 9f);
            Controls.Add(status);

            timer.Interval = 200;
            timer.Tick += delegate { Refresh_(); };
            host.Resize += delegate { LayoutScreen(); };
            KeyDown += delegate(object s, KeyEventArgs e) { OnKey(e, true); };
            KeyUp += delegate(object s, KeyEventArgs e) { OnKey(e, false); };
            Shown += OnShown;
            FormClosed += delegate { timer.Stop(); if (emu != null) { emu.DetachScreen(); emu.Stop(); emu.Dispose(); emu = null; } };
        }

        Button AddButton(Panel p, string text, ref int y, EventHandler click)
        {
            Button b = new Button();
            b.Text = text; b.SetBounds(8, y, 230, 26); b.TabStop = false;
            b.Click += click;
            p.Controls.Add(b);
            y += 30;
            return b;
        }

        void OnShown(object sender, EventArgs e)
        {
            emu = new Emulator(SpectrumModel.Spectrum128K, romDir);
            frameCallback = delegate(IntPtr user) { callbackFrames++; };
            emu.SetFrameCallback(frameCallback);
            emu.Start();
            CreatePanel();
            timer.Start();
            if (selfTest)
            {
                // The checks look at the screen: nothing may be over the panel
                TopMost = true;
                Activate();
                BeginInvoke((MethodInvoker)RunSelfTest);
            }
        }

        // The panel (a control of this form) is where the engine draws
        void CreatePanel()
        {
            if (screen != null) return;
            screen = new ScreenPanel();
            host.Controls.Add(screen);
            LayoutScreen();
            emu.AttachScreen(screen.Handle);
        }

        void DestroyPanel()
        {
            if (screen == null) return;
            emu.DetachScreen();            // the engine stops drawing in it ...
            host.Controls.Remove(screen);  // ... before it goes
            screen.Dispose();
            screen = null;
        }

        void LayoutScreen()
        {
            if (screen == null) return;
            screen.SetBounds(host.Padding.Left, host.Padding.Top,
                Math.Max(1, host.ClientSize.Width - host.Padding.Horizontal),
                Math.Max(1, host.ClientSize.Height - host.Padding.Vertical));
        }

        void TogglePause()
        {
            if (emu.State.Paused != 0) emu.Resume(); else emu.Pause();
            Refresh_();
        }

        // DI; loop: LD A,(C000); OUT (FE),A; JR loop: the border follows the byte at C000
        void LoadTestProgram()
        {
            emu.LoadRam(0x8000, new byte[] { 0xF3, 0x3A, 0x00, 0xC0, 0xD3, 0xFE, 0x18, 0xF9 });
            Refresh_();
        }

        void Refresh_()
        {
            if (emu == null) return;
            PzxState s = emu.State;
            pauseButton.Text = s.Paused != 0 ? "Resume" : "Pause";
            PzxPaging pg = emu.Paging;
            regs.Text = string.Format(
                "AF {0:X4}  BC {1:X4}\r\nDE {2:X4}  HL {3:X4}\r\nIX {4:X4}  IY {5:X4}\r\nSP {6:X4}  PC {7:X4}\r\n" +
                "7FFD {8:X2}  1FFD {9:X2}\r\nslots {10} {11} {12} {13}\r\nbreak: {14}",
                emu.GetReg(Reg.AF), emu.GetReg(Reg.BC), emu.GetReg(Reg.DE), emu.GetReg(Reg.HL),
                emu.GetReg(Reg.IX), emu.GetReg(Reg.IY), emu.GetReg(Reg.SP), emu.GetReg(Reg.PC),
                pg.Port7FFD, pg.Port1FFD, pg.Slot0, pg.Slot1, pg.Slot2, pg.Slot3, emu.BreakReason);
            status.Text = string.Format(" frames {0}  {1} fps  {2}  panel {3}",
                s.Frames, s.Fps, s.Paused != 0 ? "paused" : "running", screen != null ? screen.Width + "x" + screen.Height : "none");
        }

        // The host owns the keyboard: its keys become the Spectrum's
        void OnKey(KeyEventArgs e, bool down)
        {
            if (emu == null) return;
            int key = -1;
            if (e.KeyCode == Keys.ShiftKey || e.KeyCode == Keys.LShiftKey) key = 0;
            else if (e.KeyCode == Keys.RShiftKey || e.KeyCode == Keys.ControlKey) key = 36;
            else if (e.KeyCode == Keys.Enter) key = 30;
            else if (e.KeyCode == Keys.Space) key = 35;
            else
            {
                char c = e.KeyCode >= Keys.A && e.KeyCode <= Keys.Z ? (char)('A' + (e.KeyCode - Keys.A)) :
                    e.KeyCode >= Keys.D0 && e.KeyCode <= Keys.D9 ? (char)('0' + (e.KeyCode - Keys.D0)) : '\0';
                if (c != '\0')
                    for (int r = 0; r < 8 && key < 0; r++)
                        for (int b = 0; b < 5; b++)
                            if (KeyRows[r][b] == c) { key = r * 5 + b; break; }
            }
            if (key >= 0) { emu.Key(key, down); e.Handled = true; }
        }

        // ---------------------------------------------------------------- self test

        void Wait(int ms)
        {
            Stopwatch w = Stopwatch.StartNew();
            while (w.ElapsedMilliseconds < ms) { Application.DoEvents(); System.Threading.Thread.Sleep(5); }
        }

        void Check(bool ok, string what)
        {
            string line = (ok ? "PASS  " : "FAIL  ") + what;
            log.AppendLine(line);
            Console.WriteLine(line);
            if (!ok) failures++;
        }

        string OutDir { get { return Path.GetDirectoryName(Application.ExecutablePath); } }

        // What is on screen where the panel is (the engine's drawing, as it shows)
        Bitmap Shot(string name)
        {
            Application.DoEvents();
            Rectangle r = screen.RectangleToScreen(screen.ClientRectangle);
            Bitmap bmp = new Bitmap(r.Width, r.Height, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp)) g.CopyFromScreen(r.Location, Point.Empty, r.Size);
            bmp.Save(Path.Combine(OutDir, name + ".png"), ImageFormat.Png);
            return bmp;
        }

        static Rectangle NonBlack(Bitmap b, out int colours)
        {
            int x0 = int.MaxValue, y0 = int.MaxValue, x1 = -1, y1 = -1;
            HashSet<int> seen = new HashSet<int>();
            for (int y = 0; y < b.Height; y += 1)
                for (int x = 0; x < b.Width; x += 1)
                {
                    int c = b.GetPixel(x, y).ToArgb() & 0xFFFFFF;
                    if (c == 0) continue;
                    if (seen.Count < 64) seen.Add(c);
                    if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
                }
            colours = seen.Count;
            return x1 < 0 ? Rectangle.Empty : Rectangle.FromLTRB(x0, y0, x1 + 1, y1 + 1);
        }

        static Rectangle Expected(Size c)
        {
            int dw = c.Width, dh = c.Width * 288 / 352;
            if (dh > c.Height) { dh = c.Height; dw = c.Height * 352 / 288; }
            return new Rectangle((c.Width - dw) / 2, (c.Height - dh) / 2, dw, dh);
        }

        [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
        delegate bool EnumProc(IntPtr h, IntPtr l);

        static int VisibleTopLevelWindows()
        {
            uint me = (uint)Process.GetCurrentProcess().Id;
            int n = 0;
            EnumWindows(delegate(IntPtr h, IntPtr l)
            {
                uint pid; GetWindowThreadProcessId(h, out pid);
                if (pid == me && IsWindowVisible(h)) n++;
                return true;
            }, IntPtr.Zero);
            return n;
        }

        static bool Near(Color c, int r, int g, int b, int tol)
        {
            return Math.Abs(c.R - r) <= tol && Math.Abs(c.G - g) <= tol && Math.Abs(c.B - b) <= tol;
        }

        void RunSelfTest()
        {
            try { SelfTest(); }
            catch (Exception ex) { Check(false, "exception: " + ex); }
            File.WriteAllText(Path.Combine(OutDir, "selftest.log"), log.ToString());
            Console.WriteLine(failures == 0 ? "ALL PASSED" : failures + " FAILED");
            Environment.ExitCode = failures == 0 ? 0 : 1;
            Close();
        }

        void SelfTest()
        {
            int colours;
            // 1. the library is in this process
            bool loaded = false;
            foreach (ProcessModule m in Process.GetCurrentProcess().Modules)
                if (m.ModuleName.ToLower() == "pzxlib.dll") loaded = true;
            Check(Emulator.ApiVersion == 1 && loaded, "pzxlib.dll is loaded in this process (API version " + Emulator.ApiVersion + ")");
            Check(emu.State.Running == 1 && emu.State.Attached == 1, "the engine runs and the panel is attached");

            // 2. the screen is in the panel, no window of the engine
            Wait(2500);
            Bitmap shot = Shot("1-panel");
            Rectangle box = NonBlack(shot, out colours);
            Check(!box.IsEmpty && colours >= 2, "the Spectrum's screen is drawn inside the panel (picture " + box + ", " + colours + " colours)");
            Check(VisibleTopLevelWindows() == 1, "no other window: " + VisibleTopLevelWindows() + " visible top-level window(s) in the process");
            Rectangle exp = Expected(screen.ClientSize);
            Check(Math.Abs(box.Width - exp.Width) <= 3 && Math.Abs(box.Height - exp.Height) <= 3,
                "the picture fills the panel in proportion (expected " + exp.Size + ", is " + box.Size + ")");

            // 3. it updates while running
            long f1 = emu.State.Frames; Wait(500); long f2 = emu.State.Frames;
            Check(f2 - f1 >= 15, "the machine runs: " + (f2 - f1) + " frames in half a second");
            Check(callbackFrames > 0, "the frame callback was called (" + callbackFrames + ")");
            int w, h;
            byte[] fb = emu.GetFrame(1, out w, out h);
            bool anyColour = false;
            for (int i = 0; i < fb.Length; i += 4) if (fb[i] != 0 || fb[i + 1] != 0 || fb[i + 2] != 0) { anyColour = true; break; }
            Check(w == 352 && h == 288 && fb.Length == 352 * 288 * 4 && anyColour, "pzx_get_frame gives the picture (" + w + "x" + h + ")");

            // 4. resizing
            Size[] sizes = { new Size(1300, 800), new Size(820, 520), new Size(1040, 640) };
            foreach (Size sz in sizes)
            {
                ClientSize = sz;
                Wait(600);
                Bitmap b2 = Shot("2-resized-" + sz.Width);
                Rectangle bb = NonBlack(b2, out colours);
                Rectangle ex2 = Expected(screen.ClientSize);
                Check(Math.Abs(bb.Width - ex2.Width) <= 3 && Math.Abs(bb.Height - ex2.Height) <= 3 &&
                      Math.Abs(bb.Left - ex2.Left) <= 3 && Math.Abs(bb.Top - ex2.Top) <= 3,
                    "resized to panel " + screen.ClientSize + ": picture " + bb + ", expected " + ex2);
            }

            // 5. pause, registers, memory
            emu.Pause();
            Wait(150);
            long p1 = emu.State.Frames; Wait(300); long p2 = emu.State.Frames;
            Check(emu.State.Paused == 1 && p1 == p2, "paused: the frame count stays at " + p1);
            emu.SetReg(Reg.HL, 0x1234); emu.SetReg(Reg.BC, 0xBEEF); emu.SetReg(Reg.AF, 0xA55A);
            Check(emu.GetReg(Reg.HL) == 0x1234 && emu.GetReg(Reg.BC) == 0xBEEF && emu.GetReg(Reg.AF) == 0xA55A, "registers written and read back");
            byte[] prog = { 0xF3, 0x3A, 0x00, 0xC0, 0xD3, 0xFE, 0x18, 0xF9 };
            emu.LoadRam(0x8000, prog);
            byte[] back = emu.ReadMemory(0x8000, prog.Length);
            Check(Convert.ToBase64String(back) == Convert.ToBase64String(prog), "a program loaded in RAM and read back");

            // 6. paging and its effect on what runs
            emu.WritePort(0x7FFD, 0x10);
            emu.WriteRamBank(0, 0, new byte[] { 2 });    // bank 0: red border
            emu.WriteRamBank(1, 0, new byte[] { 5 });    // bank 1: cyan border
            Check(emu.RamBankCount == 8 && emu.ReadRamBank(1, 0, 1)[0] == 5, "physical RAM banks written and read (" + emu.RamBankCount + " banks)");
            Check(emu.Paging.Slot3 == 0 && emu.ReadMemory(0xC000, 1)[0] == 2, "bank 0 is paged in at C000");
            emu.SetReg(Reg.PC, 0x8000);
            emu.Resume();
            Wait(700);
            Bitmap red = Shot("3-bank0");
            int bx = NonBlack(red, out colours).Left + 4, by = NonBlack(red, out colours).Top + 4;
            Check(Near(red.GetPixel(bx, by), 205, 0, 0, 40), "bank 0 at C000: the border is red " + red.GetPixel(bx, by));
            emu.WritePort(0x7FFD, 0x11);
            Wait(700);
            Bitmap cyan = Shot("4-bank1");
            Check(emu.Paging.Slot3 == 1 && emu.ReadMemory(0xC000, 1)[0] == 5, "the paging changed: bank 1 at C000");
            Check(Near(cyan.GetPixel(bx, by), 0, 205, 205, 40), "bank 1 at C000: the same program now gives a cyan border " + cyan.GetPixel(bx, by));

            // 7. breakpoint and stepping
            emu.SetBreakpoint(0x8001, Emulator.BpExec);
            Wait(500);
            PzxState st = emu.State;
            Check(st.Paused == 1 && st.BreakKind == 1 && st.PC == 0x8001 && emu.BreakReason.Length > 0,
                "execution breakpoint at 8001: stopped at " + st.PC.ToString("X4") + " (" + emu.BreakReason + ")");
            emu.ClearBreakpoints();
            emu.StepInto();
            Check(emu.GetReg(Reg.PC) == 0x8004 && emu.GetReg(Reg.AF) >> 8 == 5, "one step: LD A,(C000) done, PC = " + emu.GetReg(Reg.PC).ToString("X4"));
            emu.Resume();
            Wait(300);

            // 8. the panel destroyed and created again, the machine kept
            long before = emu.State.Frames;
            byte[] marker = emu.ReadMemory(0x8000, prog.Length);
            DestroyPanel();
            Wait(500);
            Check(emu.State.Attached == 0 && emu.State.Frames > before + 10, "the panel was destroyed and the machine went on (" + (emu.State.Frames - before) + " frames)");
            CreatePanel();
            Wait(800);
            Bitmap again = Shot("5-recreated");
            Rectangle box3 = NonBlack(again, out colours);
            Check(!box3.IsEmpty && colours >= 2 && Near(again.GetPixel(box3.Left + 4, box3.Top + 4), 0, 205, 205, 40),
                "a new panel shows the same machine, with its state (cyan border)");
            Check(Convert.ToBase64String(emu.ReadMemory(0x8000, prog.Length)) == Convert.ToBase64String(marker), "memory kept across the panel's life");

            // 9. the model changes
            emu.Pause();
            emu.Model = SpectrumModel.Spectrum48K;
            emu.Reset(true);
            emu.Resume();
            Wait(1500);
            Check(emu.Model == SpectrumModel.Spectrum48K && emu.RamBankCount >= 3, "the model changed to the 48K");
            Shot("6-48k");
        }
    }

    static class Program
    {
        [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

        [STAThread]
        static int Main(string[] args)
        {
            bool self = false;
            string roms = null;
            foreach (string a in args) { if (a == "--selftest") self = true; else roms = a; }
            if (roms == null)
            {
                string dir = Path.GetDirectoryName(Application.ExecutablePath);
                for (int i = 0; i < 8 && roms == null; i++)
                {
                    string c = Path.Combine(dir, "roms");
                    if (Directory.Exists(c)) roms = c;
                    dir = Path.GetDirectoryName(dir);
                    if (dir == null) break;
                }
            }
            if (roms == null || !Directory.Exists(roms)) { Console.WriteLine("The roms folder was not found: pass it as an argument"); return 2; }
            // Real pixels (the self test looks at the screen, and the engine draws in pixels)
            SetProcessDPIAware();
            Application.EnableVisualStyles();
            MainForm f = new MainForm(roms, self);
            Application.Run(f);
            return Environment.ExitCode;
        }
    }
}
