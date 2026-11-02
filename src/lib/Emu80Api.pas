{ Emu80Api: the emulation engine as a native library for a host application (a
  C# GUI, through P/Invoke). Everything here is plain C calls (cdecl) on
  opaque handles; the host application and the engine live in the same
  process, and the engine is the same one the emu80 program runs (TEmulator and
  TSpectrum): this unit only wraps it.

  The picture: the host gives a window to draw in (emu80_attach_window: on
  Windows, the HWND of its control or panel); a presenter thread draws the
  frames there as they come, fitted to the window's size, and keeps up with
  the window being resized. The host may as well take the frames itself
  (emu80_get_frame, with emu80_set_frame_callback to know when one is ready) and
  draw them with its own toolkit. The scaling, black and white and
  deinterlacing are those of the program's window (FramePresenter).

  Input is the host's: it tells the keys (emu80_key) and the joystick; emu80
  has no window of its own here. }
unit Emu80Api;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, SyncObjs, Models, Z80Core, Spectrum, Sam, C64, C64Disk, Emulator, FramePresenter, Snapshot, Tape, Disasm;

type
  TEmu80FrameCallback = procedure(User: Pointer); cdecl;

  { C-compatible records (4-byte fields) }
  TEmu80State = record
    Running: Int32;        // the emulation thread exists (emu80_start .. emu80_stop)
    Paused: Int32;         // paused by emu80_pause, a breakpoint or stepping
    BreakKind: Int32;      // 0 none, 1 execution, 2 memory, 3 port, 4 run-to, 5 DAAD
    Model: Int32;
    PC: Int32;
    FramesLow: Int32;      // frames run since the machine was created (low and high 32 bits)
    FramesHigh: Int32;
    Fps: Int32;
    Attached: Int32;       // a window is attached
    TapePlaying: Int32;
  end;

  TEmu80Paging = record
    Port7FFD: Int32;       // last value written to 7FFD (128K family, ZX-Uno, Next)
    Port1FFD: Int32;       // and to 1FFD (+2A/+3)
    Slot0, Slot1, Slot2, Slot3: Int32;   // what is paged in each 16K slot: a RAM bank
                                         // (0-7), -1 - ROM number, or -1000 for nothing
    DivActive: Int32;      // the DivMMC is paged in at 0000
    CurrahPaged: Int32;
    UnoConf, UnoMapper: Int32;
  end;

{ Every call returns 0 (or a count / a handle) on success and a negative
  number on failure; emu80_last_error says why. }

function emu80_version: Int32; cdecl;
function emu80_create(Model: Int32; RomDir: PAnsiChar): Pointer; cdecl;
procedure emu80_destroy(H: Pointer); cdecl;
function emu80_last_error(H: Pointer; Buf: PAnsiChar; Size: Int32): Int32; cdecl;
function emu80_set_model(H: Pointer; Model: Int32): Int32; cdecl;
function emu80_get_model(H: Pointer): Int32; cdecl;
function emu80_set_next_dir(H: Pointer; Dir: PAnsiChar): Int32; cdecl;

function emu80_start(H: Pointer): Int32; cdecl;
function emu80_stop(H: Pointer): Int32; cdecl;
function emu80_pause(H: Pointer): Int32; cdecl;
function emu80_resume(H: Pointer): Int32; cdecl;
function emu80_reset(H: Pointer; Hard: Int32): Int32; cdecl;
function emu80_set_sound(H: Pointer; Enabled: Int32): Int32; cdecl;
function emu80_set_turbo(H: Pointer; Enabled: Int32): Int32; cdecl;

function emu80_attach_window(H: Pointer; Window: Pointer): Int32; cdecl;
function emu80_detach_window(H: Pointer): Int32; cdecl;
function emu80_set_display(H: Pointer; Deinterlace, Mono, Scanlines: Int32): Int32; cdecl;
function emu80_set_frame_callback(H: Pointer; Callback: TEmu80FrameCallback; User: Pointer): Int32; cdecl;
function emu80_get_frame(H: Pointer; Buf: Pointer; Size: Int32; Scale: Int32; Width, Height: PInt32): Int32; cdecl;

function emu80_get_reg(H: Pointer; Reg: Int32; Value: PInt32): Int32; cdecl;
function emu80_set_reg(H: Pointer; Reg: Int32; Value: Int32): Int32; cdecl;

function emu80_read_mem(H: Pointer; Addr: Int32; Buf: PByte; Len: Int32): Int32; cdecl;
function emu80_write_mem(H: Pointer; Addr: Int32; Buf: PByte; Len: Int32): Int32; cdecl;
function emu80_set_rom_writable(H: Pointer; Enabled: Int32): Int32; cdecl;
function emu80_ram_bank_count(H: Pointer): Int32; cdecl;
function emu80_read_ram_bank(H: Pointer; Bank, Offset: Int32; Buf: PByte; Len: Int32): Int32; cdecl;
function emu80_write_ram_bank(H: Pointer; Bank, Offset: Int32; Buf: PByte; Len: Int32): Int32; cdecl;

function emu80_get_paging(H: Pointer; Paging: Pointer): Int32; cdecl;
function emu80_write_port(H: Pointer; Port, Value: Int32): Int32; cdecl;
function emu80_set_slot3_bank(H: Pointer; Bank: Int32): Int32; cdecl;
function emu80_next_reg_get(H: Pointer; Reg: Int32): Int32; cdecl;
function emu80_next_reg_set(H: Pointer; Reg, Value: Int32): Int32; cdecl;

function emu80_set_breakpoint(H: Pointer; Addr, Flags: Int32): Int32; cdecl;
function emu80_get_breakpoint(H: Pointer; Addr: Int32): Int32; cdecl;
function emu80_clear_breakpoints(H: Pointer): Int32; cdecl;
function emu80_step_into(H: Pointer): Int32; cdecl;
function emu80_step_over(H: Pointer): Int32; cdecl;
function emu80_run_to(H: Pointer; Addr: Int32): Int32; cdecl;

function emu80_get_state(H: Pointer; State: Pointer): Int32; cdecl;
function emu80_get_break_reason(H: Pointer; Buf: PAnsiChar; Size: Int32): Int32; cdecl;

function emu80_load_ram(H: Pointer; Addr: Int32; Data: PByte; Len: Int32): Int32; cdecl;
function emu80_load_file(H: Pointer; FileName: PAnsiChar): Int32; cdecl;

function emu80_key(H: Pointer; Key: Int32; Down: Int32): Int32; cdecl;
function emu80_set_kempston(H: Pointer; Bits: Int32): Int32; cdecl;

implementation

const
  API_VERSION = 1;
  { emu80_get_reg / emu80_set_reg }
  REG_AF = 0; REG_BC = 1; REG_DE = 2; REG_HL = 3; REG_AF2 = 4; REG_BC2 = 5; REG_DE2 = 6; REG_HL2 = 7;
  REG_IX = 8; REG_IY = 9; REG_SP = 10; REG_PC = 11; REG_I = 12; REG_R = 13; REG_IM = 14;
  REG_IFF1 = 15; REG_IFF2 = 16;

type
  TEmu80Instance = class;

  { Draws the frames into the host's window }
  TPresenter = class(TThread)
  private
    FOwner: TEmu80Instance;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TEmu80Instance);
  end;

  TEmu80Instance = class
  public
    Emu: TEmulator;
    Window: PtrUInt;                 // the host's window (0: none)
    Options: TPresentOptions;
    Presenter: TPresenter;
    Dirty: Boolean;                  // draw again at once (the window or the options changed)
    Callback: TEmu80FrameCallback;
    CallbackUser: Pointer;
    Err: string;
    C64Joy: Byte;
    constructor Create(AModel: TSpectrumModel; const RomDir: string);
    destructor Destroy; override;
    procedure HostFrame(Sender: TObject);
  end;

var
  Registry: TList;
  RegistryLock: TCriticalSection;

function Find(H: Pointer): TEmu80Instance;
begin
  Result := nil;
  RegistryLock.Enter;
  try
    if Registry.IndexOf(H) >= 0 then Result := TEmu80Instance(H);
  finally
    RegistryLock.Leave;
  end;
end;

{ TEmu80Instance }

constructor TEmu80Instance.Create(AModel: TSpectrumModel; const RomDir: string);
begin
  inherited Create;
  Emu := TEmulator.Create(AModel, RomDir);
  Emu.Hosted := True;
  Emu.OnHostFrame := @HostFrame;
  Options.Deinterlace := dlProgressive;
  Options.Scanlines := False;
  Options.Fine := False;
  Options.Monitor := 0;
end;

destructor TEmu80Instance.Destroy;
begin
  Callback := nil;
  if Presenter <> nil then
  begin
    Presenter.Terminate;
    Presenter.WaitFor;
    Presenter.Free;
  end;
  Emu.Free;
  inherited Destroy;
end;

procedure TEmu80Instance.HostFrame(Sender: TObject);
var
  Cb: TEmu80FrameCallback;
begin
  Cb := Callback;
  if Assigned(Cb) then Cb(CallbackUser);
end;

{ TPresenter }

constructor TPresenter.Create(AOwner: TEmu80Instance);
begin
  FOwner := AOwner;
  FreeOnTerminate := False;
  inherited Create(False);
end;

{$IFDEF WINDOWS}
procedure TPresenter.Execute;
var
  Cur, Prev: array of LongWord;
  Pix: array of LongWord;
  Wnd: HWND;
  DC: HDC;
  R: TRect;
  CW, CH, DW, DH, DX, DY, S, LastW, LastH: Integer;
  Odd, Force: Boolean;
  LastFrame: Int64;
  LastDraw: QWord;
  Info: BITMAPINFO;
  Brush: HBRUSH;

  procedure Fill(L, T, Rt, B: Integer);
  var
    Q: TRect;
  begin
    if (Rt <= L) or (B <= T) then Exit;
    Q := Rect(L, T, Rt, B);
    FillRect(DC, Q, Brush);
  end;

begin
  SetLength(Cur, FB_WIDTH * SCREEN_HEIGHT);
  SetLength(Prev, FB_WIDTH * SCREEN_HEIGHT);
  Brush := CreateSolidBrush(0);
  LastFrame := -1;
  LastDraw := 0;
  LastW := 0;
  LastH := 0;
  try
    while not Terminated do
    begin
      Sleep(10);
      Wnd := HWND(FOwner.Window);
      if (Wnd = 0) or not IsWindow(Wnd) then Continue;
      if not GetClientRect(Wnd, R) then Continue;
      CW := R.Right - R.Left;
      CH := R.Bottom - R.Top;
      if (CW < 2) or (CH < 2) then Continue;
      Force := FOwner.Dirty or (CW <> LastW) or (CH <> LastH);
      // New frames, or the window changed, or now and then (it may have been
      // uncovered or painted over)
      if not Force and (FOwner.Emu.Spec.FrameCount = LastFrame) and (GetTickCount64 - LastDraw < 250) then Continue;
      FOwner.Dirty := False;
      FOwner.Emu.CopyFields(@Cur[0], @Prev[0], Odd);
      LastFrame := FOwner.Emu.Spec.FrameCount;
      // Fitted to the window, keeping the picture's proportions
      DW := CW;
      DH := CW * SCREEN_HEIGHT div SCREEN_WIDTH;
      if DH > CH then
      begin
        DH := CH;
        DW := CH * SCREEN_WIDTH div SCREEN_HEIGHT;
      end;
      DX := (CW - DW) div 2;
      DY := (CH - DH) div 2;
      // Drawn at a whole scale that is at most the size it is shown at (so a
      // window that is a whole multiple of the picture is sharp), and then
      // stretched to fit
      S := DW div SCREEN_WIDTH;
      if S < 1 then S := 1;
      if S > 4 then S := 4;
      SetLength(Pix, SCREEN_WIDTH * S * SCREEN_HEIGHT * S);
      FOwner.Options.Fine := FOwner.Emu.Spec.CPC <> nil;
      PresentFrame(@Cur[0], @Prev[0], Odd, S, FOwner.Options, @Pix[0], SCREEN_WIDTH * S * 4);
      FillChar(Info, SizeOf(Info), 0);
      Info.bmiHeader.biSize := SizeOf(BITMAPINFOHEADER);
      Info.bmiHeader.biWidth := SCREEN_WIDTH * S;
      Info.bmiHeader.biHeight := -(SCREEN_HEIGHT * S);   // top-down
      Info.bmiHeader.biPlanes := 1;
      Info.bmiHeader.biBitCount := 32;
      Info.bmiHeader.biCompression := BI_RGB;
      DC := GetDC(Wnd);
      if DC = 0 then Continue;
      try
        SetStretchBltMode(DC, COLORONCOLOR);
        StretchDIBits(DC, DX, DY, DW, DH, 0, 0, SCREEN_WIDTH * S, SCREEN_HEIGHT * S, @Pix[0], Info,
          DIB_RGB_COLORS, SRCCOPY);
        // The bands around it
        Fill(0, 0, CW, DY);
        Fill(0, DY + DH, CW, CH);
        Fill(0, DY, DX, DY + DH);
        Fill(DX + DW, DY, CW, DY + DH);
      finally
        ReleaseDC(Wnd, DC);
      end;
      LastW := CW;
      LastH := CH;
      LastDraw := GetTickCount64;
    end;
  finally
    DeleteObject(Brush);
  end;
end;
{$ELSE}
procedure TPresenter.Execute;
begin
  // Only Windows can draw into a host's window: elsewhere the host takes the
  // frames itself (emu80_get_frame)
  while not Terminated do Sleep(50);
end;
{$ENDIF}

{ Helpers }

procedure SetError(H: TEmu80Instance; const Msg: string);
begin
  if H <> nil then H.Err := Msg;
end;

function FillString(const S: string; Buf: PAnsiChar; Size: Int32): Int32;
var
  N: Integer;
begin
  Result := Length(S);
  if (Buf = nil) or (Size <= 0) then Exit;
  N := Length(S);
  if N > Size - 1 then N := Size - 1;
  if N > 0 then Move(S[1], Buf^, N);
  Buf[N] := #0;
end;

{ API }

function emu80_version: Int32; cdecl;
begin
  Result := API_VERSION;
end;

function emu80_create(Model: Int32; RomDir: PAnsiChar): Pointer; cdecl;
var
  Inst: TEmu80Instance;
begin
  Result := nil;
  try
    if (Model < Ord(Low(TSpectrumModel))) or (Model > Ord(High(TSpectrumModel))) then Exit;
    Inst := TEmu80Instance.Create(TSpectrumModel(Model), string(RomDir));
    RegistryLock.Enter;
    try
      Registry.Add(Inst);
    finally
      RegistryLock.Leave;
    end;
    Result := Inst;
  except
    Result := nil;
  end;
end;

procedure emu80_destroy(H: Pointer); cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit;
  RegistryLock.Enter;
  try
    Registry.Remove(H);
  finally
    RegistryLock.Leave;
  end;
  try
    Inst.Free;
  except
  end;
end;

function emu80_last_error(H: Pointer; Buf: PAnsiChar; Size: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(FillString('invalid handle', Buf, Size));
  Result := FillString(Inst.Err, Buf, Size);
end;

function emu80_set_model(H: Pointer; Model: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Result := -1;
  Inst := Find(H);
  if Inst = nil then Exit;
  if (Model < Ord(Low(TSpectrumModel))) or (Model > Ord(High(TSpectrumModel))) then
  begin
    SetError(Inst, 'unknown model');
    Exit;
  end;
  try
    Inst.Emu.Lock;
    try
      Inst.Emu.Spec.SetModel(TSpectrumModel(Model));
    finally
      Inst.Emu.Unlock;
    end;
    Result := 0;
  except
    on E: Exception do SetError(Inst, E.Message);
  end;
end;

function emu80_get_model(H: Pointer): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Result := Ord(Inst.Emu.Spec.Model);
end;

function emu80_set_next_dir(H: Pointer; Dir: PAnsiChar): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Inst.Emu.Lock;
  try
    Inst.Emu.Spec.NextDir := string(Dir);
  finally
    Inst.Emu.Unlock;
  end;
  Result := 0;
end;

function emu80_start(H: Pointer): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  try
    Inst.Emu.Paused := False;
    Inst.Emu.Start;
    Result := 0;
  except
    on E: Exception do
    begin
      SetError(Inst, E.Message);
      Result := -1;
    end;
  end;
end;

function emu80_stop(H: Pointer): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Inst.Emu.StopThread;
  Result := 0;
end;

function emu80_pause(H: Pointer): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  if Inst.Emu.Running then Inst.Emu.PauseAndWait else Inst.Emu.Paused := True;
  Result := 0;
end;

function emu80_resume(H: Pointer): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Inst.Emu.Resume;
  Result := 0;
end;

function emu80_reset(H: Pointer; Hard: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Inst.Emu.Lock;
  try
    Inst.Emu.Spec.Reset(Hard <> 0);
  finally
    Inst.Emu.Unlock;
  end;
  Result := 0;
end;

function emu80_set_sound(H: Pointer; Enabled: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Inst.Emu.Sound := Enabled <> 0;
  Result := 0;
end;

function emu80_set_turbo(H: Pointer; Enabled: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Inst.Emu.Turbo := Enabled <> 0;
  Result := 0;
end;

function emu80_attach_window(H: Pointer; Window: Pointer): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  {$IFDEF WINDOWS}
  if (Window = nil) or not IsWindow(HWND(Window)) then
  begin
    SetError(Inst, 'not a window');
    Exit(-2);
  end;
  Inst.Window := PtrUInt(Window);
  Inst.Dirty := True;
  if Inst.Presenter = nil then Inst.Presenter := TPresenter.Create(Inst);
  Result := 0;
  {$ELSE}
  SetError(Inst, 'drawing into a host window is only available on Windows: use emu80_get_frame');
  Result := -3;
  {$ENDIF}
end;

function emu80_detach_window(H: Pointer): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  // Nothing is drawn into it after this returns: the presenter reads the
  // window only while it is set, and is waited for to be out of it
  Inst.Window := 0;
  Sleep(40);
  Result := 0;
end;

function emu80_set_display(H: Pointer; Deinterlace, Mono, Scanlines: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  if (Deinterlace < 0) or (Deinterlace > Ord(High(TDeinterlace))) then Exit(-2);
  Inst.Options.Deinterlace := TDeinterlace(Deinterlace);
  Inst.Options.Monitor := Ord(Mono <> 0);
  Inst.Options.Scanlines := Scanlines <> 0;
  Inst.Dirty := True;
  Result := 0;
end;

function emu80_set_frame_callback(H: Pointer; Callback: TEmu80FrameCallback; User: Pointer): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Inst.Callback := nil;
  Inst.CallbackUser := User;
  Inst.Callback := Callback;
  Result := 0;
end;

function emu80_get_frame(H: Pointer; Buf: Pointer; Size: Int32; Scale: Int32; Width, Height: PInt32): Int32; cdecl;
var
  Inst: TEmu80Instance;
  Cur, Prev: array of LongWord;
  Odd: Boolean;
  Need: Integer;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  if Scale < 1 then Scale := 1;
  if Scale > 8 then Scale := 8;
  Need := SCREEN_WIDTH * Scale * SCREEN_HEIGHT * Scale * 4;
  if Width <> nil then Width^ := SCREEN_WIDTH * Scale;
  if Height <> nil then Height^ := SCREEN_HEIGHT * Scale;
  if (Buf = nil) or (Size < Need) then Exit(Need);    // the size it needs
  SetLength(Cur, FB_WIDTH * SCREEN_HEIGHT);
  SetLength(Prev, FB_WIDTH * SCREEN_HEIGHT);
  Inst.Emu.CopyFields(@Cur[0], @Prev[0], Odd);
  Inst.Options.Fine := Inst.Emu.Spec.CPC <> nil;
  PresentFrame(@Cur[0], @Prev[0], Odd, Scale, Inst.Options, Buf, SCREEN_WIDTH * Scale * 4);
  Result := 0;
end;

function RegGet(Cpu: TZ80; Reg: Int32; out V: Int32): Boolean;
begin
  Result := True;
  case Reg of
    REG_AF: V := (Cpu.A shl 8) or Cpu.F;
    REG_BC: V := Cpu.BC.W;
    REG_DE: V := Cpu.DE.W;
    REG_HL: V := Cpu.HL.W;
    REG_AF2: V := (Cpu.A_ shl 8) or Cpu.F_;
    REG_BC2: V := Cpu.BC_.W;
    REG_DE2: V := Cpu.DE_.W;
    REG_HL2: V := Cpu.HL_.W;
    REG_IX: V := Cpu.IX.W;
    REG_IY: V := Cpu.IY.W;
    REG_SP: V := Cpu.SP.W;
    REG_PC: V := Cpu.PC.W;
    REG_I: V := Cpu.I;
    REG_R: V := Cpu.GetR;
    REG_IM: V := Cpu.IM;
    REG_IFF1: V := Ord(Cpu.IFF1);
    REG_IFF2: V := Ord(Cpu.IFF2);
  else
    Result := False;
  end;
end;

function emu80_get_reg(H: Pointer; Reg: Int32; Value: PInt32): Int32; cdecl;
var
  Inst: TEmu80Instance;
  V: Int32;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Inst.Emu.Lock;
  try
    if not RegGet(Inst.Emu.Spec.Cpu, Reg, V) then Exit(-2);
  finally
    Inst.Emu.Unlock;
  end;
  if Value <> nil then Value^ := V;
  Result := 0;
end;

function emu80_set_reg(H: Pointer; Reg: Int32; Value: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
  C: TZ80;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Result := 0;
  Inst.Emu.Lock;
  try
    C := Inst.Emu.Spec.Cpu;
    case Reg of
      REG_AF: begin C.A := (Value shr 8) and $FF; C.F := Value and $FF; end;
      REG_BC: C.BC.W := Value and $FFFF;
      REG_DE: C.DE.W := Value and $FFFF;
      REG_HL: C.HL.W := Value and $FFFF;
      REG_AF2: begin C.A_ := (Value shr 8) and $FF; C.F_ := Value and $FF; end;
      REG_BC2: C.BC_.W := Value and $FFFF;
      REG_DE2: C.DE_.W := Value and $FFFF;
      REG_HL2: C.HL_.W := Value and $FFFF;
      REG_IX: C.IX.W := Value and $FFFF;
      REG_IY: C.IY.W := Value and $FFFF;
      REG_SP: C.SP.W := Value and $FFFF;
      REG_PC: begin C.PC.W := Value and $FFFF; C.Halted := False; end;
      REG_I: C.I := Value and $FF;
      REG_R: begin C.R := Value and $7F; C.R7 := Value and $80; end;
      REG_IM: C.IM := Value and 3;
      REG_IFF1: C.IFF1 := Value <> 0;
      REG_IFF2: C.IFF2 := Value <> 0;
    else
      Result := -2;
    end;
  finally
    Inst.Emu.Unlock;
  end;
end;

function emu80_read_mem(H: Pointer; Addr: Int32; Buf: PByte; Len: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
  I: Integer;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  if (Buf = nil) or (Len < 0) or (Addr < 0) or (Addr + Len > $10000) then Exit(-2);
  Inst.Emu.Lock;
  try
    for I := 0 to Len - 1 do Buf[I] := Inst.Emu.Spec.Peek(Word(Addr + I));
  finally
    Inst.Emu.Unlock;
  end;
  Result := Len;
end;

function emu80_write_mem(H: Pointer; Addr: Int32; Buf: PByte; Len: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
  I: Integer;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  if (Buf = nil) or (Len < 0) or (Addr < 0) or (Addr + Len > $10000) then Exit(-2);
  Inst.Emu.Lock;
  try
    for I := 0 to Len - 1 do Inst.Emu.Spec.Poke(Word(Addr + I), Buf[I]);
  finally
    Inst.Emu.Unlock;
  end;
  Result := Len;
end;

function emu80_set_rom_writable(H: Pointer; Enabled: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Inst.Emu.Spec.RomWritable := Enabled <> 0;
  Result := 0;
end;

function BankCount(Spec: TSpectrum): Integer;
begin
  case Spec.Info.Memory of
    mkZXNext: Result := RAM_BANKS;
    mkZXUno: Result := 32;
    mkCPC: Result := Spec.CPC.RamBanks;
    mkSAM: Result := Spec.SamMemoryKB div 16;
  else
    Result := 8;
  end;
end;

function emu80_ram_bank_count(H: Pointer): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Result := BankCount(Inst.Emu.Spec);
end;

function BankAccess(H: Pointer; Bank, Offset: Int32; Buf: PByte; Len: Int32; Write: Boolean): Int32;
var
  Inst: TEmu80Instance;
  P: PByte;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  if (Buf = nil) or (Len < 0) or (Offset < 0) or (Offset + Len > $4000) or (Bank < 0) or
     (Bank >= BankCount(Inst.Emu.Spec)) then Exit(-2);
  Inst.Emu.Lock;
  try
    P := PByte(Inst.Emu.Spec.RamBank(Bank));
    if Write then Move(Buf^, P[Offset], Len) else Move(P[Offset], Buf^, Len);
  finally
    Inst.Emu.Unlock;
  end;
  Result := Len;
end;

function emu80_read_ram_bank(H: Pointer; Bank, Offset: Int32; Buf: PByte; Len: Int32): Int32; cdecl;
begin
  Result := BankAccess(H, Bank, Offset, Buf, Len, False);
end;

function emu80_write_ram_bank(H: Pointer; Bank, Offset: Int32; Buf: PByte; Len: Int32): Int32; cdecl;
begin
  Result := BankAccess(H, Bank, Offset, Buf, Len, True);
end;

function emu80_get_paging(H: Pointer; Paging: Pointer): Int32; cdecl;
var
  Inst: TEmu80Instance;
  P: ^TEmu80Paging;
  S: TPagingState;
begin
  Inst := Find(H);
  if (Inst = nil) or (Paging = nil) then Exit(-1);
  P := Paging;
  Inst.Emu.Lock;
  try
    S := Inst.Emu.Spec.PagingState;
    P^.Port7FFD := Inst.Emu.Spec.Port7FFD;
    P^.Port1FFD := Inst.Emu.Spec.Port1FFD;
    P^.Slot0 := S.Slots[0];
    P^.Slot1 := S.Slots[1];
    P^.Slot2 := S.Slots[2];
    P^.Slot3 := S.Slots[3];
    P^.DivActive := Ord(S.DivActive);
    P^.CurrahPaged := Ord(S.CurrahPaged);
    P^.UnoConf := S.UnoConf;
    P^.UnoMapper := S.UnoMapper;
    // A SAM Coupe: its paging registers are what the +3's and the ZX-Uno's fields hold
    if IsSAMModel(Inst.Emu.Spec.Model) then
    begin
      P^.Port7FFD := Inst.Emu.Spec.SamRegister($FA);   // LMPR
      P^.Port1FFD := Inst.Emu.Spec.SamRegister($FB);   // HMPR
      P^.UnoConf := Inst.Emu.Spec.SamRegister($FC);    // VMPR
      P^.UnoMapper := 0;
    end;
  finally
    Inst.Emu.Unlock;
  end;
  Result := 0;
end;

function emu80_write_port(H: Pointer; Port, Value: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Result := 0;
  Inst.Emu.Lock;
  try
    if IsSAMModel(Inst.Emu.Spec.Model) then
    begin
      // The SAM Coupe's: F9 (line interrupt), FA (LMPR), FB (HMPR), FC (VMPR), FE (border);
      // F8 with the CLUT entry in the high byte
      case Port and $FF of
        $F9, $FA, $FB, $FC, $FE: Inst.Emu.Spec.SetSamRegister(Port and $FF, Value and $FF);
        $F8: Inst.Emu.Spec.SetSamRegister($100 + ((Port shr 8) and $0F), Value and $7F);
      else
        Result := -2;
      end;
    end
    else
    case Port and $FFFF of
      $7FFD: Inst.Emu.Spec.WritePaging7FFD(Value and $FF);
      $1FFD: Inst.Emu.Spec.WritePaging1FFD(Value and $FF);
    else
      Result := -2;
    end;
  finally
    Inst.Emu.Unlock;
  end;
end;

function emu80_set_slot3_bank(H: Pointer; Bank: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Inst.Emu.Lock;
  try
    if Inst.Emu.Spec.SetSlot3Bank(Bank) then Result := 0 else Result := -2;
  finally
    Inst.Emu.Unlock;
  end;
end;

function emu80_next_reg_get(H: Pointer; Reg: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Inst.Emu.Lock;
  try
    Result := Inst.Emu.Spec.NextRegister(Reg and $FF);
  finally
    Inst.Emu.Unlock;
  end;
end;

function emu80_next_reg_set(H: Pointer; Reg, Value: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Inst.Emu.Lock;
  try
    Inst.Emu.Spec.SetNextRegister(Reg and $FF, Value and $FF);
  finally
    Inst.Emu.Unlock;
  end;
  Result := 0;
end;

function emu80_set_breakpoint(H: Pointer; Addr, Flags: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Inst.Emu.Lock;
  try
    Inst.Emu.Spec.Breakpoint[Word(Addr)] := Byte(Flags);
  finally
    Inst.Emu.Unlock;
  end;
  Result := 0;
end;

function emu80_get_breakpoint(H: Pointer; Addr: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Result := Inst.Emu.Spec.Breakpoint[Word(Addr)];
end;

function emu80_clear_breakpoints(H: Pointer): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Inst.Emu.Lock;
  try
    Inst.Emu.Spec.ClearBreakpoints;
  finally
    Inst.Emu.Unlock;
  end;
  Result := 0;
end;

{ Stepping needs the machine to be stopped: it is paused first (and stays so) }
procedure PauseForStep(Inst: TEmu80Instance);
begin
  if Inst.Emu.Running then Inst.Emu.PauseAndWait else Inst.Emu.Paused := True;
end;

function emu80_step_into(H: Pointer): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  PauseForStep(Inst);
  Inst.Emu.StepInto;
  Result := 0;
end;

function emu80_step_over(H: Pointer): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  PauseForStep(Inst);
  Inst.Emu.StepOver;
  Result := 0;
end;

function emu80_run_to(H: Pointer; Addr: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  PauseForStep(Inst);
  Inst.Emu.RunTo(Word(Addr));
  Result := 0;
end;

function emu80_get_state(H: Pointer; State: Pointer): Int32; cdecl;
var
  Inst: TEmu80Instance;
  S: ^TEmu80State;
  F: Int64;
begin
  Inst := Find(H);
  if (Inst = nil) or (State = nil) then Exit(-1);
  S := State;
  S^.Running := Ord(Inst.Emu.Running);
  S^.Paused := Ord(Inst.Emu.Paused);
  S^.BreakKind := Ord(Inst.Emu.Spec.BreakKind);
  S^.Model := Ord(Inst.Emu.Spec.Model);
  S^.PC := Inst.Emu.Spec.Cpu.PC.W;
  F := Inst.Emu.Spec.FrameCount;
  S^.FramesLow := Int32(F and $FFFFFFFF);
  S^.FramesHigh := Int32(F shr 32);
  S^.Fps := Inst.Emu.Fps;
  S^.Attached := Ord(Inst.Window <> 0);
  S^.TapePlaying := Ord(Inst.Emu.Spec.Tape.Playing);
  Result := 0;
end;

function emu80_get_break_reason(H: Pointer; Buf: PAnsiChar; Size: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Result := FillString(Inst.Emu.Spec.BreakReason, Buf, Size);
end;

function emu80_load_ram(H: Pointer; Addr: Int32; Data: PByte; Len: Int32): Int32; cdecl;
begin
  Result := emu80_write_mem(H, Addr, Data, Len);
end;

function emu80_load_file(H: Pointer; FileName: PAnsiChar): Int32; cdecl;
var
  Inst: TEmu80Instance;
  Ext, Name: string;
  Disk: TD64Image;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Name := string(FileName);
  Ext := LowerCase(ExtractFileExt(Name));
  Result := 0;
  Inst.Emu.Lock;
  try
    try
      // A Commodore 64: a disk goes in drive 8, a program is put in and run, a tape (.tap) is played
      if IsC64Model(Inst.Emu.Spec.Model) and ((Ext = '.d64') or (Ext = '.prg') or (Ext = '.p00') or (Ext = '.t64') or (Ext = '.tap')) then
      begin
        if Ext = '.d64' then
        begin
          Disk := TD64Image.Create;
          try
            Disk.LoadFromFile(Name);
          except
            Disk.Free;
            raise;
          end;
          Inst.Emu.Spec.C64Hw.InsertDisk(0, Disk);
          Inst.Emu.Spec.AutoLoad(True);
        end
        else if Ext = '.tap' then
        begin
          Inst.Emu.Spec.C64Hw.InsertTape(Name);
          Inst.Emu.Spec.AutoLoad(False);
        end
        else
        begin
          Inst.Emu.Spec.Reset(True);
          Inst.Emu.Spec.C64Hw.LoadPrg(Name, True);
        end;
      end
      else if (Ext = '.tap') or (Ext = '.tzx') or (Ext = '.cdt') then
      begin
        Inst.Emu.Spec.Tape.LoadFile(Name);
        Inst.Emu.Spec.AutoLoad;
      end
      else if Ext = '.sna' then LoadSNA(Inst.Emu.Spec, Name)
      else if Ext = '.z80' then LoadZ80(Inst.Emu.Spec, Name)
      else if Ext = '.e80' then Inst.Emu.Spec.LoadOwnSnapshot(Name)
      else if Ext = '.nex' then Inst.Emu.Spec.LoadNex(Name)
      else
      begin
        SetError(Inst, 'unsupported file type: ' + Ext);
        Result := -2;
      end;
    except
      on E: Exception do
      begin
        SetError(Inst, E.Message);
        Result := -3;
      end;
    end;
  finally
    Inst.Emu.Unlock;
  end;
end;

function emu80_key(H: Pointer; Key: Int32; Down: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
  Row, Bit: Integer;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  // A SAM Coupe: row * 8 + bit of its keyboard matrix (0-71; the SAMK_* of Sam.pas)
  if IsSAMModel(Inst.Emu.Spec.Model) then
  begin
    if (Key < 0) or (Key >= SAMK_COUNT) then Exit(-2);
    Inst.Emu.Lock;
    try
      with Inst.Emu.Spec.SAM do
        if Down <> 0 then Keys[Key div 8] := Keys[Key div 8] or (1 shl (Key mod 8))
        else Keys[Key div 8] := Keys[Key div 8] and not (1 shl (Key mod 8));
    finally
      Inst.Emu.Unlock;
    end;
    Exit(0);
  end;
  // A Commodore 64: column * 8 + row of its keyboard matrix (0-63, the C64K_* of C64.pas), 64-68 the joystick in port 2
  // (up, down, left, right, fire) and 69 RESTORE
  if IsC64Model(Inst.Emu.Spec.Model) then
  begin
    if (Key < 0) or (Key > 69) then Exit(-2);
    Inst.Emu.Lock;
    try
      with Inst.Emu.Spec.C64Hw do
        if Key < 64 then SetKey(Key div 8, Key mod 8, Down <> 0)
        else if Key = 69 then SetRestore(Down <> 0)
        else
        begin
          if Down <> 0 then Inst.C64Joy := Inst.C64Joy or (1 shl (Key - 64)) else Inst.C64Joy := Inst.C64Joy and not (1 shl (Key - 64));
          SetJoystick(2, Inst.C64Joy);
        end;
    finally
      Inst.Emu.Unlock;
    end;
    Exit(0);
  end;
  // An Amstrad CPC: line * 8 + bit of its keyboard matrix (0-79)
  if Inst.Emu.Spec.CPC <> nil then
  begin
    if (Key < 0) or (Key > 79) then Exit(-2);
    Inst.Emu.Lock;
    try
      with Inst.Emu.Spec.CPC do
        if Down <> 0 then KeyMatrix[Key div 8] := KeyMatrix[Key div 8] and not (1 shl (Key mod 8))
        else KeyMatrix[Key div 8] := KeyMatrix[Key div 8] or (1 shl (Key mod 8));
    finally
      Inst.Emu.Unlock;
    end;
    Exit(0);
  end;
  if (Key < 0) or (Key > 39) then Exit(-2);
  Row := Key div 5;
  Bit := Key mod 5;
  Inst.Emu.Lock;
  try
    if Down <> 0 then Inst.Emu.Spec.Keyboard[Row] := Inst.Emu.Spec.Keyboard[Row] and not (1 shl Bit)
    else Inst.Emu.Spec.Keyboard[Row] := Inst.Emu.Spec.Keyboard[Row] or (1 shl Bit);
  finally
    Inst.Emu.Unlock;
  end;
  Result := 0;
end;

function emu80_set_kempston(H: Pointer; Bits: Int32): Int32; cdecl;
var
  Inst: TEmu80Instance;
begin
  Inst := Find(H);
  if Inst = nil then Exit(-1);
  Inst.Emu.Spec.KempstonEnabled := True;
  Inst.Emu.Spec.KempstonState := Byte(Bits);
  Result := 0;
end;

initialization
  Registry := TList.Create;
  RegistryLock := TCriticalSection.Create;

finalization
  RegistryLock.Free;
  Registry.Free;
end.
