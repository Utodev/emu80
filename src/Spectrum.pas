{ Spectrum: the machine. Memory paging, ULA contention, I/O decoding,
  T-state accurate video, beeper/AY audio capture and frame execution for
  all supported models. }
unit Spectrum;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  SysUtils, Classes, Math, Types, Z80Core, Models, AY8912, Tape, FDC765, BreakExpr, DivMMC, Daad;

const
  SCREEN_WIDTH = 352;
  SCREEN_HEIGHT = 288;
  { The frame buffer is twice as wide: every pixel twice, so the Timex
    512-pixel hi-res mode fits }
  FB_WIDTH = SCREEN_WIDTH * 2;
  BORDER_LEFT = 48;
  BORDER_TOP = 48;
  SAMPLE_RATE = 44100;

  PORT_LOG_SIZE = 10;  // port accesses remembered for the debugger

type
  TBank = array[0..$3FFF] of Byte;
  PBank = ^TBank;

  TAudioEvent = record
    T: Integer;
    Kind: Byte;     // 0 = beeper level, 1 = AY register write, 2 = second AY (TurboSound)
    Reg: Byte;
    Value: Byte;
  end;

  { One port access, for the debugger }
  TPortAccess = record
    PC: Word;        // address of the instruction that did it
    Port: Word;
    Value: Byte;
    Write: Boolean;
  end;

  { What stopped the emulation }
  TBreakKind = (bkNone, bkExec, bkMemory, bkPort, bkRunTo, bkDaad);

  { DAAD debugger: where to stop next. dsNext: at the next condact; dsOver:
    at the next one with SP at or above DaadSP (after a PROCESS returns) }
  TDaadStop = (dsNone, dsNext, dsOver);

const
  { ZX-Uno: 512K of SRAM in 16K pages (0-7 the RAM banks, 8-11 the ROM, 12
    the DivMMC firmware...) and a 4 MB SPI flash }
  ZXUNO_PAGES = 32;
  ZXUNO_FLASH_SIZE = 4 * 1024 * 1024;
  { The BIOS settings in the flash: active ROM, quiet boot, timings... }
  ZXUNO_CFG = $7040;
  ZXUNO_CFG_SIZE = 64;

  { DaadMap flags per address }
  DAAD_CONDACT = 1;   // a condact starts here (its opcode)
  DAAD_STREAM = 2;    // part of a condact (a parameter, or an entry's end mark)
  DAAD_ENTRY = 4;     // an entry's condact address (read when the entry runs)
  DAAD_ENTRY_HISTORY = 16;
  DAAD_BREAK = 8;     // a breakpoint on this condact
  { The player's order has been read: after this condact (DAAD's PARSE), or
    when this byte is read (the start of PAW's response table) }
  DAAD_INPUT = 16;

type
  { A DAAD breakpoint: a condact and its condition (nil = always). The
    condition belongs to whoever sets it. }
  TDaadBreak = record
    Addr: Word;
    Cond: TDaadCondition;
  end;

type

  TStereoSample = packed record
    L, R: SmallInt;
  end;

  { One step of automatic typing: keys held (or none) for a number of frames }
  TAutoKeyStep = record
    Frames: Integer;
    Rows: array[0..7] of Byte;   // bits cleared for pressed keys
  end;

  TSpectrum = class(TZ80Bus)
  private
    FModel: TSpectrumModel;
    FInfo: TModelInfo;
    FCpu: TZ80;
    FAY: TAY8912;
    FAY2: TAY8912;                       // second chip (TurboSound)
    FAYChip: Integer;                    // chip selected by port $FFFD (TurboSound)
    FAY2Levels: array[0..2] of Single;
    FMotorPhase, FNoiseLP: Single;      // floppy drive noise
    FNoiseSeed: LongWord;
    FTape: TTape;
    FFDC: TUPD765;
    FRam: array[0..ZXUNO_PAGES - 1] of TBank;   // 0-7 the RAM banks (all 32: ZX-Uno SRAM)
    FRom: array[0..3] of TBank;
    FNoMem: TBank;                       // unpopulated memory (16K): reads $FF
    FRomDir: string;
    FSlot: array[0..3] of PBank;
    FSlotBank: array[0..3] of Integer;   // RAM bank in slot, or -1 - ROM number
    FSlotContended: array[0..3] of Boolean;
    FContentionOn: Boolean;              // setting: apply memory/I/O contention
    FContend: Boolean;                   // contention applies now (setting and 1x speed)
    FSnowOn: Boolean;                    // setting: ULA snow
    FSnowPix, FSnowAttr: array[0..32 * 192 - 1] of SmallInt;   // corrupted fetches, -1 = none
    FPort7FFD: Byte;
    FPort1FFD: Byte;
    FScreenBank: Integer;
    FBorder: Byte;
    FUlaOut: Byte;          // last value written to port $FE
    FContention: array of Byte;
    FFrameBuffer: array of LongWord;
    FRenderLine: Integer;
    FRenderCell: Integer;
    FFlashCounter: Integer;
    FFlashOn: Boolean;
    FNMIRequest: Boolean;
    FFrameCount: Int64;
    // Audio
    FEvents: array of TAudioEvent;
    FEventCount: Integer;
    FBeeperLevel: Byte;
    FSamplePos: Double;      // T-state position of the next sample within the frame
    FAYTickT: Integer;       // T-state of the next AY tick within the frame
    FAYLevels: array[0..2] of Single;
    FDCPrevIn, FDCPrevOut: array[0..1] of Single;
    FSamples: array of TStereoSample;
    FSampleCount: Integer;
    FMuted: Boolean;
    FVolume: Single;
    FBreakFlags: array[0..$FFFF] of Byte;   // BP_* per address
    FBreakConds: array of TBreakCondition;  // optional condition per address
    FInstrPC: Word;                         // start of the instruction being run
    FPortLog: array[0..PORT_LOG_SIZE - 1] of TPortAccess;
    FPortLogPos: Integer;                   // next entry to write
    FPortLogCount: Integer;
    FMemBreakpoints: Integer;               // number of read/write breakpoints
    FPortBreakFlags: array[0..$FFFF] of Byte;   // BP_READ (IN) / BP_WRITE (OUT) per port
    FPortBreakConds: array of TBreakCondition;
    FPortBreakpoints: Integer;
    FProbeBus: TZ80Bus;                     // dry run of the next instruction
    FProbeCpu: TZ80;
    FProbeCovered: Boolean;                 // the probe checked the instruction being run
    FSkipProbeOnce: Boolean;
    FSuppressBreaks: Boolean;               // no access checks during the probed instruction
    FCpuTBase: Int64;                       // CPU T-states before this frame (tape recording)
    FRecorder: TTapeRecorder;
    FDiv: TDivMMC;
    FDivOn: Boolean;                        // DivMMC connected
    FResetFrame: Int64;                     // frame of the last reset
    FMicLevel: Boolean;
    FBreakHit: Boolean;
    FBreakReason: string;
    FBreakKind: TBreakKind;
    FBreakInstr: Word;                      // instruction that caused a memory/port break
    FSkipBreakOnce: Boolean;
    FTempBreak: Integer;                    // run-to address, -1 if none
    FULAPlusReg: Byte;                      // ULAplus register selected (port BF3B)
    FULAPlusMode: Byte;                     // bit 0 palette on, bit 1 Radastan
    FULAPlusPal: array[0..63] of Byte;      // GGGRRRBB
    FULAPlusRGB: array[0..63] of LongWord;
    FTimexPort: Byte;                       // Timex screen mode (port FF)
    FZXUnoReg: Byte;                        // ZX-Uno register selected (port FC3B)
    FZXReg: array[0..255] of Byte;          // ZX-Uno registers (40h RADASCTRL: 3 = Radastan)
    FZXBoot: TBank;                         // ZX-Uno: memory at 0000 in boot mode
    FZXFlash: array of Byte;                // ZX-Uno: the SPI flash (4 MB)
    FSpiBus: array[0..7] of Byte;           // command and address being sent
    FSpiIndex: Integer;
    FSpiAddr: Integer;
    FSpiNext: Byte;                         // next byte read
    FSpiStatus: Byte;                       // bit 1: write enabled
    FCoreIdPos: Integer;
    FZXUnoCfg: array[0..ZXUNO_CFG_SIZE - 1] of Byte;   // BIOS settings (flash 7040)
    FZXUnoCfgChanged: Boolean;
    FZXCustom: TBank;                       // ZX-Uno: the custom ROM
    FZXCustomOn: Boolean;                   // there is one
    FZXCustomRun: Boolean;                  // the BIOS has started it (48K, no paging)
    FZXKbdBat: Boolean;                     // the PS/2 keyboard's power-on $AA not read yet
    FUnoAutoLoad: Integer;                  // -1 none; frames since the BIOS started the ROM
    FDaadOn: Boolean;                       // watching the DAAD interpreter
    FDaadMap: array[0..$FFFF] of Byte;      // DAAD_* per address
    FDaadFetch: Integer;                    // last condact fetched, -1 if none
    FDaadFetchPC, FDaadEntryPC: Integer;    // the interpreter's reading instructions, -1 until learnt
    FDaadCandEntryPC: Integer;              // learning: instruction that read an entry's address
    FDaadCandHeader: Word;                  // learning: that entry
    FDaadExpect: Integer;                   // learning: its first condact
    FDaadCandFetchPC: Integer;              // learning: instruction that read it
    FDaadSeen: Integer;                     // learning: times that pair was seen
    FDaadStop: TDaadStop;
    FDaadSP: Word;
    FDaadStopAfterParse: Boolean;           // stop at the condact after each PARSE
    FDaadBreaks: array of TDaadBreak;       // enabled DAAD breakpoints
    FDaadBreakHit: Boolean;                 // the last DAAD stop was a breakpoint
    FDaadParsed: Boolean;                   // a PARSE has just run
    FDaadEntries: array[0..DAAD_ENTRY_HISTORY - 1] of Word;   // entries run, a ring
    FDaadEntryPos, FDaadEntryCount: Integer;
    FTrackPrev: Boolean;
    FSpeed: Integer;                        // CPU clock multiplier (1 = real)
    FPendingSpeed: Integer;
    FPrevRegs: TZ80Regs;                    // registers before the last instruction
    FAutoKeys: array of TAutoKeyStep;
    FAutoKeyPos: Integer;
    FAutoKeyFrames: Integer;
    procedure DaadRead(Addr: Word);
    procedure SetDivOn(Value: Boolean);
    procedure ZXUnoAutoLoadStep;
    function IntActive: Boolean;
    function RasterIntActive: Boolean;
    function GetZXUnoBios: string;
    procedure SetZXUnoBios(const Value: string);
    function RadastanOn: Boolean; inline;
    function HasULAPlus: Boolean; inline;
    function HasTimex: Boolean; inline;
    function HasRadastan: Boolean; inline;
    function IsZXUno: Boolean; inline;
    procedure LoadZXUnoFlash;
    procedure ZXUnoBoot(Hard: Boolean);
    procedure SetZXUnoTiming;
    procedure ZXUnoWriteReg(Reg, Value: Byte);
    function ZXUnoReadReg(Reg: Byte): Byte;
    procedure SpiWrite(Value: Byte);
    function SpiRead: Byte;
    function ULAPlusOn: Boolean; inline;
    procedure SetULAPlusEntry(Index, Value: Byte);
    function DaadFlag(N: Byte): Byte;
    procedure MarkDaadBreaks;
    procedure AdvanceAutoKeys;
    function KeyRow(Row: Integer): Byte;
    procedure BuildContention;
    procedure UpdatePaging;
    procedure LoadRoms;
    function CurrentRom: Integer;
    procedure RenderCell(Line, Cell: Integer);
    procedure SnowAt(T: Integer);
    procedure UpdateContend;
    procedure SetContentionOn(Value: Boolean);
    function ActiveAY: TAY8912;
    procedure IOContendPre(Port: Word; var T: Integer);
    procedure IOContendPost(Port: Word; var T: Integer);
    function FloatingBus(T: Integer): Byte;
    procedure AddEvent(T: Integer; Kind, Reg, Value: Byte);
    procedure TapeEdge(T: Integer; Level: Boolean);
    procedure UpdateBeeper(T: Integer);
    procedure ApplyEvent(Index: Integer);
    procedure GenerateAudio;
    procedure TapeTrap;
    procedure CheckTraps;
    procedure ExecuteOne;
    function U(T: Integer): Integer; inline;
    function FrameLength: Integer; inline;
    function FrameStartT: Int64; inline;
    procedure TapeSaveTrap;
    function ConditionHolds(Addr: Word): Boolean;
    procedure LogPort(Port: Word; Value: Byte; Write: Boolean);
    procedure SetTrackPrev(Value: Boolean);
    procedure FinishFrame;
    function GetBreakpoint(Addr: Word): Byte;
    procedure SetBreakpoint(Addr: Word; Flags: Byte);
    function GetPortBreakpoint(Port: Word): Byte;
    procedure SetPortBreakpoint(Port: Word; Flags: Byte);
    procedure CheckPortBreak(Port: Word; Write: Boolean);
    function PortBreakMatch(Port: Word; Write: Boolean): Boolean;
    function ProbeBreak: Boolean;
    function GetRecording: Boolean;
    procedure SetRecording(Value: Boolean);
  public
    Keyboard: array[0..7] of Byte;   // half-row state, bit = 0 when pressed
    KempstonState: Byte;
    KempstonEnabled: Boolean;
    FullerState: Byte;      // Fuller joystick port $7F, bits low when pressed
    FullerEnabled: Boolean;
    { 16K/48K keyboard issue 2: bit 6 of port $FE also follows the MIC output }
    Issue2: Boolean;
    { Append blocks saved by the ROM (SAVE) to the tape }
    SaveToTape: Boolean;
    FastLoad: Boolean;
    AutoPlayTape: Boolean;
    { Debugger edits and POKEs may change the ROM }
    RomWritable: Boolean;
    { The sound of the +3's drive (motor, head steps, reading) at real speed }
    FloppyNoise: Boolean;
    { Two AY chips, selected by writing $FF / $FE to port $FFFD (NedoPC) }
    TurboSound: Boolean;
    { An AY interface on the 16K/48K (ports $FFFD/$BFFD, like the 128K) }
    AYOn48K: Boolean;
    { Kempston mouse: ports $FBDF (X), $FFDF (Y) and $FADF (buttons) }
    MouseEnabled: Boolean;
    MouseX, MouseY: Byte;      // Y grows upwards
    MouseButtons: Byte;        // bits low when pressed: 0 right, 1 left, 2 middle
    { ULAplus (64-colour palette, ports BF3B/FF3B), Timex screen modes (port
      FF: second screen, hi-colour 8x1 attributes, 512x192 hi-res) and the
      ZX-Uno's Radastan mode (128x96, 16 colours) }
    ULAPlusEnabled: Boolean;
    TimexEnabled: Boolean;
    RadastanEnabled: Boolean;
    { ZX-Uno: its BIOS (FIRMWARE.ZX1) and ROMs (ROMS.ZX1, as the BIOS
      upgrades them from the SD card), and the esxDOS firmware the flash
      holds for its DivMMC }
    ZXUnoFirmware: string;
    ZXUnoRoms: string;
    ZXUnoEsxdos: string;
    { ZX-Uno custom ROM: a 16K ROM run instead of the one the BIOS chose
      ('' or a missing file = none) }
    ZXUnoCustomRom: string;
    { ROM file per model and ROM number ('' = the default file in RomDir) }
    RomFile: array[TSpectrumModel, 0..3] of string;
    constructor Create(AModel: TSpectrumModel; const ARomDir: string);
    destructor Destroy; override;
    procedure SetModel(AModel: TSpectrumModel);
    procedure Reset(Hard: Boolean);
    procedure RequestNMI;
    { Queue automatic typing. Keys is a list of "row:mask" presses; an empty
      Keys waits Frames frames with nothing pressed. }
    procedure AutoType(Frames: Integer; const Keys: array of Integer);
    procedure CancelAutoType;
    { The machine has an AY: built in, or the 16K/48K interface }
    function HasAY: Boolean;
    { True while automatic typing is queued or running }
    function AutoTyping: Boolean;
    { Type text through the keyboard: letters and digits as their keys (so
      "J" in keyword mode is LOAD), symbols with SYMBOL SHIFT ("" is SYMBOL+P),
      "~" waits half a second, escapes \n ENTER and \w wait one second. False if a
      character can't be typed (Error says which). }
    function TypeText(const Text: string; out Error: string): Boolean;
    { Full path of ROM Index for the current model }
    function RomPath(Index: Integer): string;
    { Reset and load from tape the way a user would (LOAD "" or Loader menu). }
    procedure AutoLoad;
    { Run until the end of the frame (video, audio and interrupt). Returns
      False if a breakpoint stopped it first; calling it again continues the
      same frame. }
    function RunFrame: Boolean;
    { Debugger: execute exactly one instruction (or accept an interrupt). }
    procedure StepInstruction;
    { Debugger: ignore an execution breakpoint at the current PC once, so
      execution can resume from it. }
    procedure SkipBreakpointOnce;
    procedure ClearBreakpoints;
    { Condition for the breakpoint at Addr ('' = always). False if the text
      is not a valid condition (Error says why). }
    function SetBreakCondition(Addr: Word; const Text: string; out Error: string): Boolean;
    function BreakCondition(Addr: Word): string;
    { Port breakpoints: BP_READ (IN), BP_WRITE (OUT) or both, plus
      BP_DISABLED. A port up to $FF matches on the low byte only (any high
      byte); a higher one matches the whole 16-bit port. }
    function SetPortBreakCondition(Port: Word; const Text: string; out Error: string): Boolean;
    function PortBreakCondition(Port: Word): string;
    { Last port accesses, newest first (Index 0 = most recent) }
    function PortLogCount: Integer;
    function PortLog(Index: Integer): TPortAccess;
    { Read memory as the CPU sees it, without side effects or breakpoints. }
    function Peek(Addr: Word): Byte;
    function FetchMem(Addr: Word; T: Integer): Byte; override;
    property Breakpoint[Addr: Word]: Byte read GetBreakpoint write SetBreakpoint;
    property PortBreakpoint[Port: Word]: Byte read GetPortBreakpoint write SetPortBreakpoint;
    property TempBreak: Integer read FTempBreak write FTempBreak;
    { DAAD debugger: Map has DAAD_* flags for every address (the condacts of
      the game's processes); while on, the interpreter's condact fetches are
      followed. Off with nil. }
    procedure SetDaadMap(Map: PByte);
    property DaadOn: Boolean read FDaadOn;
    property DaadStop: TDaadStop read FDaadStop write FDaadStop;
    property DaadSP: Word read FDaadSP write FDaadSP;
    { Stop at the condact after each PARSE (once the player's order is read) }
    property DaadStopAfterParse: Boolean read FDaadStopAfterParse write FDaadStopAfterParse;
    { The enabled DAAD breakpoints (they act while the map is on) }
    procedure SetDaadBreaks(const Breaks: array of TDaadBreak);
    { The last DAAD stop was at a breakpoint }
    property DaadBreakHit: Boolean read FDaadBreakHit;
    { Address of the last condact fetched, -1 if none yet }
    property DaadFetch: Integer read FDaadFetch;
    { The interpreter's condact fetch instruction, -1 until learnt (it is
      learnt when the game runs an entry) }
    property DaadFetchPC: Integer read FDaadFetchPC;
    { Header address (its verb) of the entries run lately, newest first
      (Index 0); -1 past the last one. Tells which entry a condact shared
      by several entries (DRC does that) belongs to. }
    function DaadEntry(Index: Integer): Integer;
    property BreakReason: string read FBreakReason;
    property BreakKind: TBreakKind read FBreakKind;
    { For memory and port breakpoints: the instruction that did the access
      (execution stops after it) }
    property BreakInstr: Word read FBreakInstr;
    { Times a conditional breakpoint has been reached (its T), -1 if its
      condition doesn't use T }
    function BreakHits(Addr: Word): Integer;
    function PortBreakHits(Port: Word): Integer;
    { While True, PrevRegs holds the registers from before the last
      instruction (used by the debugger to highlight changes). }
    { True when 0000-3FFF holds the 48K BASIC ROM (its labels apply) }
    function BasicRomPaged: Boolean;
    { ROM paged at 0000-3FFF, or -1 if RAM is there (+3 special paging) }
    function PagedRom: Integer;
    { What is paged in a 16K slot: RAM bank (0-7), -1 - ROM number, or NO_MEMORY }
    function SlotBank(Slot: Integer): Integer;
    { Debugger: page RAM bank 0-7 in at C000 (128K/+2/+3 normal paging).
      Ignores the paging lock. False if this machine can't. }
    function SetSlot3Bank(Bank: Integer): Boolean;
    { Debugger: write a byte where the CPU would (ROM is left unchanged) }
    procedure Poke(Addr: Word; Value: Byte);
    property TrackPrevRegs: Boolean read FTrackPrev write SetTrackPrev;
    property PrevRegs: TZ80Regs read FPrevRegs write FPrevRegs;
    procedure RenderUpTo(T: Integer);
    { Draw the frame again from its first line (tests) }
    procedure RestartRender;
    { Render the picture up to the current CPU position (after a break) }
    procedure RenderToCurrent;
    { CPU clock multiplier: 1, 2, 4 ... 32. Interrupts stay at 50 Hz; the
      change applies from the next frame. }
    procedure SetSpeed(Value: Integer);
    property Speed: Integer read FSpeed;
    { Disk transfers without real drive timing }
    procedure SetFastDisk(Value: Boolean);
    function GetFastDisk: Boolean;
    procedure WritePaging7FFD(Value: Byte);
    procedure WritePaging1FFD(Value: Byte);
    function RamBank(Index: Integer): PBank;
    // TZ80Bus
    procedure Contend(Addr: Word; Time: Integer; var T: Integer); override;
    procedure ContendNoMreq(Addr: Word; Time: Integer; var T: Integer); override;
    function ReadMem(Addr: Word; T: Integer): Byte; override;
    procedure WriteMem(Addr: Word; Value: Byte; T: Integer); override;
    function ReadPort(Port: Word; var T: Integer): Byte; override;
    procedure WritePort(Port: Word; Value: Byte; var T: Integer); override;
    { Copy of the current frame in $FFRRGGBB pixels, SCREEN_WIDTH x SCREEN_HEIGHT. }
    procedure CopyFrameBuffer(Dest: PLongWord);
    function Samples: Pointer;
    property SampleCount: Integer read FSampleCount;
    property Model: TSpectrumModel read FModel;
    property Info: TModelInfo read FInfo;
    property Cpu: TZ80 read FCpu;
    property AY: TAY8912 read FAY;
    property Tape: TTape read FTape;
    property FDC: TUPD765 read FFDC;
    property Border: Byte read FBorder write FBorder;
    property Port7FFD: Byte read FPort7FFD;
    property Port1FFD: Byte read FPort1FFD;
    property RomDir: string read FRomDir write FRomDir;
    property FrameCount: Int64 read FFrameCount;
    { Frames run since the last reset (to know if the ROM has started) }
    function FramesSinceReset: Int64;
    property Muted: Boolean read FMuted write FMuted;
    property Volume: Single read FVolume write FVolume;
    { Memory and I/O contention (off: every access takes its nominal time) }
    property ContentionOn: Boolean read FContentionOn write SetContentionOn;
    { Recording the MIC output onto the tape (REC): standard-speed blocks are
      decoded and added at the end of the tape }
    property Recording: Boolean read GetRecording write SetRecording;
    { The DivMMC interface (connected while DivMMCOn) }
    property DivMMC: TDivMMC read FDiv;
    property DivMMCOn: Boolean read FDivOn write SetDivOn;
    { ZX-Uno register (debugger) }
    function ZXUnoRegister(Reg: Byte): Byte;
    { Debugger: write a ZX-Uno register, as an OUT to FD3B would }
    procedure SetZXUnoRegister(Reg, Value: Byte);
    { Debugger: set MASTERCONF or MASTERMAPPER whatever the lock and the
      boot mode say }
    procedure DebugSetZXUnoReg(Reg, Value: Byte);
    { The ZX-Uno BIOS settings (active ROM, quiet boot, timings...), as hex:
      the BIOS saves them in its flash; set before the machine starts.
      Changed: the BIOS has saved others since }
    property ZXUnoBiosSettings: string read GetZXUnoBios write SetZXUnoBios;
    property ZXUnoBiosChanged: Boolean read FZXUnoCfgChanged write FZXUnoCfgChanged;
    { ULA snow on the models that show it (16K, 48K, 128K, +2) }
    property SnowOn: Boolean read FSnowOn write FSnowOn;
  end;

const
  { Spectrum keys as row * 5 + bit, matching the keyboard half-rows }
  KEY_CAPS = 0; KEY_Z = 1; KEY_X = 2; KEY_C = 3; KEY_V = 4;
  KEY_A = 5; KEY_S = 6; KEY_D = 7; KEY_F = 8; KEY_G = 9;
  KEY_Q = 10; KEY_W = 11; KEY_E = 12; KEY_R = 13; KEY_T = 14;
  KEY_1 = 15; KEY_2 = 16; KEY_3 = 17; KEY_4 = 18; KEY_5 = 19;
  KEY_0 = 20; KEY_9 = 21; KEY_8 = 22; KEY_7 = 23; KEY_6 = 24;
  KEY_P = 25; KEY_O = 26; KEY_I = 27; KEY_U = 28; KEY_Y = 29;
  KEY_ENTER = 30; KEY_L = 31; KEY_K = 32; KEY_J = 33; KEY_H = 34;
  KEY_SPACE = 35; KEY_SYM = 36; KEY_M = 37; KEY_N = 38; KEY_B = 39;

  NO_MEMORY = -100;   // slot with nothing paged in (16K model)

  BP_EXEC = 1;
  BP_READ = 2;
  BP_WRITE = 4;
  BP_DISABLED = $80;   // kept with its type and condition, but never stops

  Palette: array[0..15] of LongWord = (
    $FF000000, $FF0000D8, $FFD80000, $FFD800D8, $FF00D800, $FF00D8D8, $FFD8D800, $FFD8D8D8,
    $FF000000, $FF0000FF, $FFFF0000, $FFFF00FF, $FF00FF00, $FF00FFFF, $FFFFFF00, $FFFFFFFF);

implementation

type
  { Bus for the dry run of an instruction: reads memory without side
    effects, writes nothing and records every access }
  TProbeAccess = record
    Addr: Word;
    Kind: Byte;    // 0 memory read, 1 memory write, 2 port read, 3 port write
  end;

  TProbeBus = class(TZ80Bus)
  public
    Peek: function(Addr: Word): Byte of object;
    Accesses: array[0..15] of TProbeAccess;
    Count: Integer;
    procedure Add(Addr: Word; Kind: Byte);
    procedure Contend(Addr: Word; Time: Integer; var T: Integer); override;
    procedure ContendNoMreq(Addr: Word; Time: Integer; var T: Integer); override;
    function ReadMem(Addr: Word; T: Integer): Byte; override;
    function FetchMem(Addr: Word; T: Integer): Byte; override;
    procedure WriteMem(Addr: Word; Value: Byte; T: Integer); override;
    function ReadPort(Port: Word; var T: Integer): Byte; override;
    procedure WritePort(Port: Word; Value: Byte; var T: Integer); override;
  end;

procedure TProbeBus.Add(Addr: Word; Kind: Byte);
begin
  if Count > High(Accesses) then Exit;
  Accesses[Count].Addr := Addr;
  Accesses[Count].Kind := Kind;
  Inc(Count);
end;

procedure TProbeBus.Contend(Addr: Word; Time: Integer; var T: Integer);
begin
  Inc(T, Time);
end;

procedure TProbeBus.ContendNoMreq(Addr: Word; Time: Integer; var T: Integer);
begin
  Inc(T, Time);
end;

function TProbeBus.ReadMem(Addr: Word; T: Integer): Byte;
begin
  Add(Addr, 0);
  Result := Peek(Addr);
end;

function TProbeBus.FetchMem(Addr: Word; T: Integer): Byte;
begin
  Result := Peek(Addr);
end;

procedure TProbeBus.WriteMem(Addr: Word; Value: Byte; T: Integer);
begin
  Add(Addr, 1);
end;

function TProbeBus.ReadPort(Port: Word; var T: Integer): Byte;
begin
  Add(Port, 2);
  Inc(T, 4);
  Result := $FF;
end;

procedure TProbeBus.WritePort(Port: Word; Value: Byte; var T: Integer);
begin
  Add(Port, 3);
  Inc(T, 4);
end;

{ TSpectrum }

constructor TSpectrum.Create(AModel: TSpectrumModel; const ARomDir: string);
var
  I: Integer;
begin
  inherited Create;
  FRomDir := ARomDir;
  FCpu := TZ80.Create(Self);
  FAY := TAY8912.Create;
  FAY2 := TAY8912.Create;
  FTape := TTape.Create;
  FTape.OnEdge := @TapeEdge;
  FFDC := TUPD765.Create;
  FProbeBus := TProbeBus.Create;
  TProbeBus(FProbeBus).Peek := @Peek;
  FProbeCpu := TZ80.Create(FProbeBus);
  FRecorder := TTapeRecorder.Create(FTape);
  FDiv := TDivMMC.Create;
  // ZX-Uno files next to the ROM folder; its BIOS showing its boot screen
  // and starting the first ROM (the 48K)
  ZXUnoFirmware := ExtractFilePath(ExcludeTrailingPathDelimiter(ARomDir)) + 'zxuno' +
    PathDelim + 'FIRMWARE.ZX1';
  ZXUnoRoms := ExtractFilePath(ExcludeTrailingPathDelimiter(ARomDir)) + 'zxuno' +
    PathDelim + 'ROMS.ZX1';
  SetZXUnoBios('');
  ZXUnoEsxdos := ExtractFilePath(ExcludeTrailingPathDelimiter(ARomDir)) + 'esxdos' +
    PathDelim + 'ESXMMC.BIN';
  FFDC.Timed := True;
  SetLength(FFrameBuffer, FB_WIDTH * SCREEN_HEIGHT);
  FillChar(FNoMem, SizeOf(FNoMem), $FF);
  SetLength(FEvents, 4096);
  SetLength(FSamples, 2048);
  for I := 0 to 7 do Keyboard[I] := $FF;
  KempstonEnabled := True;
  FullerState := $FF;
  MouseButtons := $FF;
  SaveToTape := True;
  FSpeed := 1;
  FPendingSpeed := 1;
  FTempBreak := -1;
  FUnoAutoLoad := -1;
  FDaadFetch := -1;
  FastLoad := True;
  AutoPlayTape := True;
  FVolume := 0.7;
  FContentionOn := True;
  FSnowOn := True;
  FloppyNoise := True;
  FNoiseSeed := 12345;
  ConditionPeek := @Peek;    // @x in breakpoint conditions
  SetModel(AModel);
end;

destructor TSpectrum.Destroy;
begin
  ClearBreakpoints;
  FRecorder.Free;
  FDiv.Free;
  FProbeCpu.Free;
  FProbeBus.Free;
  FFDC.Free;
  FTape.Free;
  FAY2.Free;
  FAY.Free;
  FCpu.Free;
  inherited Destroy;
end;

procedure TSpectrum.LoadRoms;
var
  I: Integer;
  S: TFileStream;
  FileName: string;
begin
  if FInfo.Memory = mkZXUno then
  begin
    LoadZXUnoFlash;
    Exit;
  end;
  for I := 0 to FInfo.RomCount - 1 do
  begin
    FileName := RomPath(I);
    if not FileExists(FileName) then
      raise Exception.CreateFmt('ROM file not found: %s', [FileName]);
    S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      FillChar(FRom[I], SizeOf(TBank), $FF);
      S.Read(FRom[I], SizeOf(TBank));
    finally
      S.Free;
    end;
  end;
end;

function TSpectrum.RomPath(Index: Integer): string;
begin
  Result := RomFile[FModel, Index and 3];
  if Result = '' then
    Result := IncludeTrailingPathDelimiter(FRomDir) + FInfo.RomFiles[Index and 3]
  else if not ((Result[1] in ['/', '\']) or ((Length(Result) > 1) and (Result[2] = ':'))) then
    Result := IncludeTrailingPathDelimiter(FRomDir) + Result;
end;

procedure TSpectrum.SetModel(AModel: TSpectrumModel);
var
  WasUno: Boolean;
begin
  WasUno := IsZXUno;
  FModel := AModel;
  FInfo := ModelInfo[AModel];
  LoadRoms;
  // The ZX-Uno's DivMMC has its firmware in SRAM page 12 and its RAM in
  // pages 16-23 (so MASTERMAPPER sees it too); leaving it, the interface is
  // off until its firmware is loaded again
  if IsZXUno then FDiv.UseMemory(@FRam[12], @FRam[16])
  else
  begin
    FDiv.UseMemory(nil, nil);
    if WasUno then FDivOn := False;
  end;
  BuildContention;
  FTape.ClockHz := FInfo.ClockHz;
  FFDC.ClockHz := FInfo.ClockHz;
  UpdateContend;
  Reset(True);
end;

procedure TSpectrum.BuildContention;
var
  Line, X, T: Integer;
begin
  SetLength(FContention, FInfo.FrameT + 2000);
  FillChar(FContention[0], Length(FContention), 0);
  for Line := 0 to 191 do
    for X := 0 to 127 do
    begin
      T := FInfo.ContentionStartT + Line * FInfo.LineT + X;
      FContention[T] := FInfo.ContentionPattern[X and 7];
    end;
end;

procedure TSpectrum.Reset(Hard: Boolean);
var
  I: Integer;
begin
  if Hard then
  begin
    for I := 0 to 7 do FillChar(FRam[I], SizeOf(TBank), 0);
    for I := 0 to 63 do SetULAPlusEntry(I, 0);
  end;
  FULAPlusReg := 0;
  FULAPlusMode := 0;
  FTimexPort := 0;
  FZXUnoReg := 0;
  FZXReg[$40] := 0;
  if IsZXUno then ZXUnoBoot(Hard);
  FCpu.Reset(Hard);
  FCpu.T := 0;
  FAY.Reset;
  FAY2.Reset;
  FDiv.Reset(Hard);
  FResetFrame := FFrameCount;
  FAYChip := 0;
  FillChar(FSnowPix, SizeOf(FSnowPix), $FF);
  FillChar(FSnowAttr, SizeOf(FSnowAttr), $FF);
  FFDC.Reset;
  FPort7FFD := 0;
  FPort1FFD := 0;
  FBorder := 7;
  FUlaOut := 0;
  FNMIRequest := False;
  FUnoAutoLoad := -1;
  CancelAutoType;
  FRenderLine := 0;
  FRenderCell := 0;
  FEventCount := 0;
  FBeeperLevel := 0;
  FSamplePos := 0;
  FAYTickT := 0;
  UpdatePaging;
end;

procedure TSpectrum.RequestNMI;
begin
  FNMIRequest := True;
end;

function TSpectrum.RamBank(Index: Integer): PBank;
begin
  Result := @FRam[Index and 7];
end;

procedure TSpectrum.UpdatePaging;
const
  SpecialMaps: array[0..3, 0..3] of Integer = (
    (0, 1, 2, 3), (4, 5, 6, 7), (4, 5, 6, 3), (4, 7, 6, 3));
var
  Slot, Bank, Rom: Integer;
begin
  case FInfo.Memory of
    mk48K:
      begin
        FSlotBank[0] := -1;
        FSlotBank[1] := 5;
        if FInfo.Ram16K then
        begin
          FSlotBank[2] := NO_MEMORY;
          FSlotBank[3] := NO_MEMORY;
        end
        else
        begin
          FSlotBank[2] := 2;
          FSlotBank[3] := 0;
        end;
        FScreenBank := 5;
      end;
    mk128K:
      begin
        FSlotBank[0] := -1 - ((FPort7FFD shr 4) and 1);
        FSlotBank[1] := 5;
        FSlotBank[2] := 2;
        FSlotBank[3] := FPort7FFD and 7;
      end;
    mkZXUno:
      if (FZXReg[0] and 1) <> 0 then
      begin
        // Boot mode: the boot ROM, banks 5 and 2, and the SRAM page chosen
        // by MASTERMAPPER at C000
        FSlotBank[0] := -5;
        FSlotBank[1] := 5;
        FSlotBank[2] := 2;
        FSlotBank[3] := FZXReg[1] and (ZXUNO_PAGES - 1);
      end
      else if (FPort1FFD and 1) <> 0 then
      begin
        for Slot := 0 to 3 do
          FSlotBank[Slot] := SpecialMaps[(FPort1FFD shr 1) and 3, Slot];
      end
      else
      begin
        // As the +2A; the ROM (SRAM pages 8-11) bits can be fixed by
        // DEVCONTROL (DIROM7F bit 4, DIROM1F bit 5)
        Rom := 0;
        if (FZXReg[$0E] and $10) = 0 then Rom := (FPort7FFD shr 4) and 1;
        if (FZXReg[$0E] and $20) = 0 then Rom := Rom or ((FPort1FFD shr 1) and 2);
        FSlotBank[0] := -1 - Rom;
        FSlotBank[1] := 5;
        FSlotBank[2] := 2;
        FSlotBank[3] := FPort7FFD and 7;
      end;
    mkPlus3:
      if (FPort1FFD and 1) <> 0 then
      begin
        for Slot := 0 to 3 do
          FSlotBank[Slot] := SpecialMaps[(FPort1FFD shr 1) and 3, Slot];
      end
      else
      begin
        Rom := ((FPort7FFD shr 4) and 1) or ((FPort1FFD shr 1) and 2);
        FSlotBank[0] := -1 - Rom;
        FSlotBank[1] := 5;
        FSlotBank[2] := 2;
        FSlotBank[3] := FPort7FFD and 7;
      end;
  end;
  if FInfo.Memory <> mk48K then
  begin
    if (FPort7FFD and $08) <> 0 then FScreenBank := 7 else FScreenBank := 5;
  end;

  for Slot := 0 to 3 do
  begin
    Bank := FSlotBank[Slot];
    if Bank = NO_MEMORY then
    begin
      FSlot[Slot] := @FNoMem;
      FSlotContended[Slot] := False;
    end
    else if Bank < 0 then
    begin
      if not IsZXUno then FSlot[Slot] := @FRom[-1 - Bank]
      else if Bank = -5 then FSlot[Slot] := @FZXBoot
      else FSlot[Slot] := @FRam[8 + (-1 - Bank)];   // ZX-Uno: ROMs in SRAM pages 8-11
      FSlotContended[Slot] := False;
    end
    else
    begin
      FSlot[Slot] := @FRam[Bank];
      case FInfo.Memory of
        mk48K: FSlotContended[Slot] := Bank = 5;
        mk128K: FSlotContended[Slot] := Odd(Bank);
        mkPlus3: FSlotContended[Slot] := Bank >= 4;
        mkZXUno: FSlotContended[Slot] := (Bank < 8) and Odd(Bank);
      end;
    end;
  end;
end;

function TSpectrum.CurrentRom: Integer;
begin
  if (FSlotBank[0] < 0) and (FSlotBank[0] <> NO_MEMORY) then Result := -1 - FSlotBank[0]
  else Result := -1;
end;

function TSpectrum.SlotBank(Slot: Integer): Integer;
begin
  Result := FSlotBank[Slot and 3];
end;

procedure TSpectrum.SetTrackPrev(Value: Boolean);
begin
  // Until an instruction runs, "before the last instruction" is "now"
  if Value and not FTrackPrev then FPrevRegs := FCpu.GetRegs;
  FTrackPrev := Value;
end;

{ ULA time: the CPU may run faster than the ULA (CPU speed setting) }
function TSpectrum.U(T: Integer): Integer;
begin
  Result := T div FSpeed;
end;

{ Frame length in CPU T-states }
function TSpectrum.FrameLength: Integer;
begin
  Result := FInfo.FrameT * FSpeed;
end;

{ Absolute ULA time at the start of this frame }
function TSpectrum.FrameStartT: Int64;
begin
  Result := FFrameCount * FInfo.FrameT;
end;

procedure TSpectrum.SetSpeed(Value: Integer);
begin
  if Value < 1 then Value := 1;
  if Value > 32 then Value := 32;
  FPendingSpeed := Value;
end;

procedure TSpectrum.SetFastDisk(Value: Boolean);
begin
  FFDC.Timed := not Value;
end;

function TSpectrum.GetFastDisk: Boolean;
begin
  Result := not FFDC.Timed;
end;

procedure TSpectrum.RenderToCurrent;
begin
  RenderUpTo(U(FCpu.T));
end;

function TSpectrum.SetSlot3Bank(Bank: Integer): Boolean;
begin
  Result := (FInfo.Memory <> mk48K) and ((FPort1FFD and 1) = 0);
  if not Result then Exit;
  FPort7FFD := (FPort7FFD and $F8) or (Bank and 7);
  UpdatePaging;
end;

function TSpectrum.PagedRom: Integer;
begin
  Result := CurrentRom;
end;

procedure TSpectrum.Poke(Addr: Word; Value: Byte);
var
  Bank: Integer;
begin
  if FDivOn and (Addr < $4000) and FDiv.Active then
  begin
    FDiv.Write(Addr, Value);
    Exit;
  end;
  Bank := FSlotBank[Addr shr 14];
  if (Bank = NO_MEMORY) or ((Bank < 0) and not RomWritable) then Exit;
  FSlot[Addr shr 14]^[Addr and $3FFF] := Value;
end;

function TSpectrum.FramesSinceReset: Int64;
begin
  Result := FFrameCount - FResetFrame;
end;

function TSpectrum.HasAY: Boolean;
begin
  if IsZXUno then Result := (FZXReg[$0E] and 1) = 0   // DEVCONTROL.DIAY
  else Result := FInfo.HasAY or AYOn48K;
end;

procedure TSpectrum.UpdateContend;
begin
  FContend := FContentionOn and (FSpeed = 1);
end;

procedure TSpectrum.SetContentionOn(Value: Boolean);
begin
  FContentionOn := Value;
  UpdateContend;
end;

function TSpectrum.ActiveAY: TAY8912;
begin
  if TurboSound and (FAYChip = 1) then Result := FAY2 else Result := FAY;
end;

function TSpectrum.BasicRomPaged: Boolean;
begin
  // ZX-Uno: whatever ROM its BIOS chose; the 48K BASIC has LD-BYTES at 0556
  if IsZXUno then
    Result := (FSlotBank[0] < 0) and (FSlotBank[0] <> -5) and (FSlot[0]^[$0556] = $14) and
      (FSlot[0]^[$0557] = $08) and (FSlot[0]^[$0558] = $15) and (FSlot[0]^[$0559] = $F3)
  else
    Result := CurrentRom = FInfo.BasicRom;
end;

procedure TSpectrum.WritePaging7FFD(Value: Byte);
begin
  if FInfo.Memory = mk48K then Exit;
  if ((Value xor FPort7FFD) and $08) <> 0 then RenderUpTo(U(FCpu.T));
  FPort7FFD := Value;
  UpdatePaging;
end;

procedure TSpectrum.WritePaging1FFD(Value: Byte);
begin
  if not (FInfo.Memory in [mkPlus3, mkZXUno]) then Exit;
  FPort1FFD := Value;
  FFDC.Motor := (Value and $08) <> 0;
  UpdatePaging;
end;

{ Memory access }

procedure TSpectrum.Contend(Addr: Word; Time: Integer; var T: Integer);
begin
  if FContend and FSlotContended[Addr shr 14] then Inc(T, FContention[T]);
  Inc(T, Time);
end;

procedure TSpectrum.ContendNoMreq(Addr: Word; Time: Integer; var T: Integer);
begin
  if FInfo.NoMreqContention and FContend and FSlotContended[Addr shr 14] then
    Inc(T, FContention[T]);
  Inc(T, Time);
end;

function TSpectrum.ReadMem(Addr: Word; T: Integer): Byte;
begin
  if FDivOn and (Addr < $4000) and FDiv.Active then
    Result := FDiv.Read(Addr)
  else
    Result := FSlot[Addr shr 14]^[Addr and $3FFF];
  if FDaadOn and (FDaadMap[Addr] <> 0) then DaadRead(Addr);
  if (FMemBreakpoints > 0) and not FSuppressBreaks and
     ((FBreakFlags[Addr] and (BP_READ or BP_DISABLED)) = BP_READ) and ConditionHolds(Addr) then
  begin
    FBreakHit := True;
    FBreakKind := bkMemory;
    FBreakInstr := FInstrPC;
    FBreakReason := Format('Read breakpoint at %.4X (instruction at %.4X)', [Addr, FInstrPC]);
  end;
end;

{ A read in the processes of a DAAD game. Other code reads them too (the
  128K interpreter copies data around), so the interpreter's own reads are
  learnt first: when an entry runs, one instruction reads the address of
  its condacts from the entry and then another reads the first one: the
  condact fetch. Once the same pair has been seen twice, only reads by
  those two instructions count (the fetch's parameter read, at another
  instruction, doesn't). Block instructions (LDIR...) are never them. }
procedure TSpectrum.DaadRead(Addr: Word);
var
  I: Integer;

  procedure AddEntry(Header: Word);
  begin
    FDaadEntries[FDaadEntryPos] := Header;
    FDaadEntryPos := (FDaadEntryPos + 1) mod DAAD_ENTRY_HISTORY;
    if FDaadEntryCount < DAAD_ENTRY_HISTORY then Inc(FDaadEntryCount);
  end;

begin
  if (FDaadMap[Addr] and DAAD_ENTRY) <> 0 then
  begin
    if FDaadEntryPC >= 0 then
    begin
      // The interpreter takes the address of an entry's condacts: it runs it
      if FInstrPC = FDaadEntryPC then AddEntry(Word(Addr - 2));
    end
    else if Peek(FInstrPC) <> $ED then
    begin
      FDaadCandEntryPC := FInstrPC;
      FDaadCandHeader := Word(Addr - 2);
      FDaadExpect := Peek(Addr) or (Peek(Word(Addr + 1)) shl 8);
    end;
    Exit;
  end;
  if (FDaadMap[Addr] and (DAAD_INPUT or DAAD_CONDACT)) = DAAD_INPUT then
  begin
    // PAW scans the response table once it has the player's order
    FDaadParsed := True;
    Exit;
  end;
  if (FDaadMap[Addr] and DAAD_CONDACT) = 0 then Exit;
  if FDaadFetchPC < 0 then
  begin
    if (Addr <> FDaadExpect) or (Peek(FInstrPC) = $ED) then Exit;
    FDaadExpect := -1;
    if (FDaadSeen > 0) and (FInstrPC = FDaadCandFetchPC) then Inc(FDaadSeen) else FDaadSeen := 1;
    FDaadCandFetchPC := FInstrPC;
    if FDaadSeen < 2 then Exit;
    FDaadFetchPC := FInstrPC;
    FDaadEntryPC := FDaadCandEntryPC;
    AddEntry(FDaadCandHeader);
  end
  else if FInstrPC <> FDaadFetchPC then
    Exit;
  FDaadFetch := Addr;
  if FDaadParsed then
  begin
    // The condact after a PARSE: the order has been read
    FDaadParsed := False;
    if FDaadStopAfterParse then FDaadStop := dsNext;
  end;
  if (FDaadMap[Addr] and DAAD_INPUT) <> 0 then FDaadParsed := True;
  FDaadBreakHit := False;
  if (FDaadMap[Addr] and DAAD_BREAK) <> 0 then
    for I := 0 to High(FDaadBreaks) do
      if (FDaadBreaks[I].Addr = Addr) and
         ((FDaadBreaks[I].Cond = nil) or FDaadBreaks[I].Cond.Holds(@DaadFlag)) then
      begin
        FDaadBreakHit := True;
        FDaadStop := dsNext;
        Break;
      end;
  if (FDaadStop = dsNext) or ((FDaadStop = dsOver) and (FCpu.SP.W >= FDaadSP)) then
  begin
    // Stops after the instruction that read it
    FDaadStop := dsNone;
    FBreakHit := True;
    FBreakKind := bkDaad;
    FBreakInstr := FInstrPC;
    FBreakReason := '';
  end;
end;

{ Flag N of the game: IX points at the flags while a condact runs }
function TSpectrum.DaadFlag(N: Byte): Byte;
begin
  Result := Peek(Word(FCpu.IX.W + N));
end;

procedure TSpectrum.MarkDaadBreaks;
var
  A, I: Integer;
begin
  for A := 0 to $FFFF do FDaadMap[A] := FDaadMap[A] and not DAAD_BREAK;
  for I := 0 to High(FDaadBreaks) do
    FDaadMap[FDaadBreaks[I].Addr] := FDaadMap[FDaadBreaks[I].Addr] or DAAD_BREAK;
end;

procedure TSpectrum.SetDaadBreaks(const Breaks: array of TDaadBreak);
var
  I: Integer;
begin
  SetLength(FDaadBreaks, Length(Breaks));
  for I := 0 to High(Breaks) do FDaadBreaks[I] := Breaks[I];
  MarkDaadBreaks;
end;

procedure TSpectrum.SetDaadMap(Map: PByte);
begin
  FDaadOn := Map <> nil;
  if FDaadOn then
  begin
    Move(Map^, FDaadMap, SizeOf(FDaadMap));
    MarkDaadBreaks;
  end;
  FDaadFetch := -1;
  FDaadFetchPC := -1;
  FDaadEntryPC := -1;
  FDaadExpect := -1;
  FDaadSeen := 0;
  FDaadStop := dsNone;
  FDaadParsed := False;
  FDaadEntryCount := 0;
end;

function TSpectrum.DaadEntry(Index: Integer): Integer;
begin
  if (Index < 0) or (Index >= FDaadEntryCount) then Exit(-1);
  Result := FDaadEntries[(FDaadEntryPos - 1 - Index + DAAD_ENTRY_HISTORY * 2) mod DAAD_ENTRY_HISTORY];
end;

function TSpectrum.FetchMem(Addr: Word; T: Integer): Byte;
begin
  // Opcode fetches never trigger read breakpoints
  if FDivOn and (Addr < $4000) then
  begin
    // DivMMC automatic paging happens around opcode fetches
    FDiv.BeforeFetch(Addr);
    if FDiv.Active then Result := FDiv.Read(Addr) else Result := FSlot[0]^[Addr];
    FDiv.AfterFetch(Addr);
  end
  else
    Result := FSlot[Addr shr 14]^[Addr and $3FFF];
  // ULA snow: with I pointing at contended memory, the refresh cycle (the
  // last two T-states of the M1 cycle) disturbs a screen fetch at that time
  if FSnowOn and (FSpeed = 1) and FSlotContended[FCpu.I shr 6] and (FInfo.Memory <> mkPlus3) then
  begin
    SnowAt(T - 2);
    SnowAt(T - 1);
  end;
end;

{ A refresh cycle at T: if the ULA fetches a screen byte then, it gets the
  byte whose low address byte is R instead. }
procedure TSpectrum.SnowAt(T: Integer);
var
  Rel, Line, X, Col, Addr: Integer;
  Value: SmallInt;
begin
  Rel := T - (FInfo.ContentionStartT + 1);
  if Rel < 0 then Exit;
  Line := Rel div FInfo.LineT;
  X := Rel mod FInfo.LineT;
  if (Line >= 192) or (X >= 128) or ((X and 7) > 3) then Exit;
  // Fetch order in each 8 T-states: bitmap, attribute, bitmap, attribute
  Col := ((X shr 2) and $FE) + ((X and 7) shr 1);
  if Odd(X) then
    Addr := $1800 + (Line shr 3) * 32 + Col
  else
    Addr := ((Line and $C0) shl 5) or ((Line and 7) shl 8) or ((Line and $38) shl 2) or Col;
  Value := FRam[FScreenBank][(Addr and $3F00) or FCpu.GetR];
  if Odd(X) then FSnowAttr[Line * 32 + Col] := Value else FSnowPix[Line * 32 + Col] := Value;
  // Already drawn: draw that cell again with the corrupted byte
  if (FRenderLine > Line + BORDER_TOP) or
     ((FRenderLine = Line + BORDER_TOP) and (FRenderCell > Col + BORDER_LEFT div 8)) then
    RenderCell(Line + BORDER_TOP, Col + BORDER_LEFT div 8);
end;

function TSpectrum.Peek(Addr: Word): Byte;
begin
  if FDivOn and (Addr < $4000) and FDiv.Active then
    Result := FDiv.Read(Addr)
  else
    Result := FSlot[Addr shr 14]^[Addr and $3FFF];
end;

procedure TSpectrum.WriteMem(Addr: Word; Value: Byte; T: Integer);
var
  Slot: Integer;
begin
  Slot := Addr shr 14;
  if (FMemBreakpoints > 0) and not FSuppressBreaks and
     ((FBreakFlags[Addr] and (BP_WRITE or BP_DISABLED)) = BP_WRITE) and ConditionHolds(Addr) then
  begin
    FBreakHit := True;
    FBreakKind := bkMemory;
    FBreakInstr := FInstrPC;
    FBreakReason := Format('Write breakpoint at %.4X (instruction at %.4X)', [Addr, FInstrPC]);
  end;
  if FDivOn and (Addr < $4000) and FDiv.Active then
  begin
    FDiv.Write(Addr, Value);
    Exit;
  end;
  if FSlotBank[Slot] < 0 then Exit;  // ROM
  if (FSlotBank[Slot] = FScreenBank) and ((Addr and $3FFF) < 6912) then
    RenderUpTo(U(T));
  FSlot[Slot]^[Addr and $3FFF] := Value;
end;

{ I/O }

procedure TSpectrum.IOContendPre(Port: Word; var T: Integer);
begin
  if FInfo.IOContention and FContend and FSlotContended[Port shr 14] then
    Inc(T, FContention[T]);
  Inc(T);
end;

procedure TSpectrum.IOContendPost(Port: Word; var T: Integer);
var
  N: Integer;
begin
  if not FInfo.IOContention or not FContend then
  begin
    Inc(T, 3);
    Exit;
  end;
  if (Port and 1) <> 0 then
  begin
    if FSlotContended[Port shr 14] then
      for N := 1 to 3 do
      begin
        Inc(T, FContention[T]);
        Inc(T);
      end
    else
      Inc(T, 3);
  end
  else
  begin
    Inc(T, FContention[T]);
    Inc(T, 3);
  end;
end;

function TSpectrum.FloatingBus(T: Integer): Byte;
var
  Rel, Line, X, Col: Integer;
begin
  Result := $FF;
  // First bitmap fetch is one T-state after contention starts (verified with
  // Ramsoft's floatspy on 48K and 128K timings)
  Rel := T - (FInfo.ContentionStartT + 1);
  if Rel < 0 then Exit;
  Line := Rel div FInfo.LineT;
  X := Rel mod FInfo.LineT;
  if (Line >= 192) or (X >= 128) then Exit;
  Col := (X shr 2) and $FE;
  case X and 7 of
    0: Result := FRam[FScreenBank][((Line and $C0) shl 5) or ((Line and 7) shl 8) or ((Line and $38) shl 2) or Col];
    1: Result := FRam[FScreenBank][$1800 + (Line shr 3) * 32 + Col];
    2: Result := FRam[FScreenBank][((Line and $C0) shl 5) or ((Line and 7) shl 8) or ((Line and $38) shl 2) or (Col + 1)];
    3: Result := FRam[FScreenBank][$1800 + (Line shr 3) * 32 + Col + 1];
  end;
end;

function TSpectrum.ReadPort(Port: Word; var T: Integer): Byte;
var
  Row: Integer;
  Responded: Boolean;
  HighByte: Byte;
begin
  IOContendPre(Port, T);
  Result := $FF;
  Responded := False;

  if (Port and 1) = 0 then
  begin
    // ULA: keyboard, EAR
    Responded := True;
    HighByte := Port shr 8;
    for Row := 0 to 7 do
      if (HighByte and (1 shl Row)) = 0 then Result := Result and KeyRow(Row);
    Result := Result or $A0;
    FTape.AdvanceTo(U(T));
    if FTape.Playing then
    begin
      if not FTape.Level then Result := Result and not $40;
    end
    else if Issue2 and (FInfo.Memory = mk48K) then
    begin
      // Issue 2: EAR input follows either the EAR or the MIC output
      if (FUlaOut and $18) = 0 then Result := Result and not $40;
    end
    else if (FUlaOut and $10) = 0 then
      Result := Result and not $40;
  end
  else if FDivOn and FDiv.IsPort(Port) then
  begin
    Responded := True;
    Result := FDiv.ReadPort(Port);
  end
  // The ZX-Uno has its Kempston joystick port always (its BIOS reads it)
  else if (KempstonEnabled or IsZXUno) and ((Port and $E0) = 0) then
  begin
    Responded := True;
    Result := KempstonState;
  end
  else if MouseEnabled and ((Port and $FF) = $DF) then
  begin
    // Kempston mouse decodes A8 and A10 to pick the register
    Responded := True;
    case Port and $0500 of
      $0100: Result := MouseX;          // FBDF
      $0500: Result := MouseY;          // FFDF
      $0000: Result := MouseButtons;    // FADF
    else
      Responded := False;
    end;
  end
  else if FullerEnabled and ((Port and $FF) = $7F) then
  begin
    Responded := True;
    Result := FullerState;
  end
  else if HasAY and ((Port and $C002) = $C000) then
  begin
    Responded := True;
    Result := ActiveAY.ReadData;
  end
  else if FInfo.HasFDC and ((Port and $F002) = $2000) then
  begin
    Responded := True;
    FFDC.SetTime(FrameStartT + U(T));
    Result := FFDC.ReadStatus;
  end
  else if FInfo.HasFDC and ((Port and $F002) = $3000) then
  begin
    Responded := True;
    FFDC.SetTime(FrameStartT + U(T));
    Result := FFDC.ReadData;
  end;

  if IsZXUno and (Port = $FC3B) then
  begin
    Responded := True;
    Result := FZXUnoReg;
  end
  else if IsZXUno and (Port = $FD3B) then
  begin
    Responded := True;
    Result := ZXUnoReadReg(FZXUnoReg);
  end
  else if (HasULAPlus or HasRadastan) and (Port = $FF3B) then
  begin
    Responded := True;
    if (FULAPlusReg shr 6) = 0 then Result := FULAPlusPal[FULAPlusReg and $3F]
    else Result := FULAPlusMode;
  end
  else if HasRadastan and (Port = $FD3B) and (FZXUnoReg = $40) then
  begin
    Responded := True;
    Result := FZXReg[$40];
  end
  else if HasTimex and ((Port and $FF) = $FF) then
  begin
    // The Timex screen mode register, instead of the floating bus
    Responded := True;
    Result := FTimexPort;
  end;

  if not Responded and FInfo.FloatingBus then
    Result := FloatingBus(U(T));
  LogPort(Port, Result, False);
  CheckPortBreak(Port, False);

  IOContendPost(Port, T);
end;

procedure TSpectrum.WritePort(Port: Word; Value: Byte; var T: Integer);
begin
  IOContendPre(Port, T);
  LogPort(Port, Value, True);
  CheckPortBreak(Port, True);

  if (Port and 1) = 0 then
  begin
    if (Value and 7) <> FBorder then
    begin
      RenderUpTo(U(T));
      FBorder := Value and 7;
    end;
    FUlaOut := Value;
    UpdateBeeper(U(T));
    // REC: the MIC output (EAR too, as on the real socket)
    if FRecorder.Active and (((Value and $18) <> 0) <> FMicLevel) then
    begin
      FMicLevel := not FMicLevel;
      FRecorder.Edge(FCpuTBase + T);   // CPU T-states: what the ROM's loops count
    end;
  end;

  if FDivOn and FDiv.IsPort(Port) then FDiv.WritePort(Port, Value);

  // Video modes: draw what is already shown before the change
  if IsZXUno and (Port = $FC3B) then
  begin
    FZXUnoReg := Value;
    FCoreIdPos := 0;
  end
  else if IsZXUno and (Port = $FD3B) then
    ZXUnoWriteReg(FZXUnoReg, Value)
  else if (HasULAPlus or HasRadastan) and (Port = $BF3B) then
    FULAPlusReg := Value
  else if (HasULAPlus or HasRadastan) and (Port = $FF3B) then
  begin
    RenderUpTo(U(T));
    case FULAPlusReg shr 6 of
      0: SetULAPlusEntry(FULAPlusReg and $3F, Value);
      1: FULAPlusMode := Value;
    end;
  end
  else if HasRadastan and (Port = $FC3B) then
    FZXUnoReg := Value
  else if HasRadastan and (Port = $FD3B) then
  begin
    if FZXUnoReg = $40 then
    begin
      RenderUpTo(U(T));
      FZXReg[$40] := Value;
    end;
  end
  else if HasTimex and ((Port and $FF) = $FF) then
  begin
    RenderUpTo(U(T));
    FTimexPort := Value;
  end;

  case FInfo.Memory of
    mk128K:
      if (Port and $8002) = 0 then
        if (FPort7FFD and $20) = 0 then WritePaging7FFD(Value);
    mkZXUno:
      // DEVCONTROL can switch off 7FFD (bit 2) and 1FFD (bit 3): with both
      // on, +2A decoding; with only 7FFD, 128K decoding (new_memory.v)
      if ((FPort7FFD and $20) = 0) and ((FZXReg[$0E] and 4) = 0) then
      begin
        if (FZXReg[$0E] and 8) = 0 then
        begin
          if (Port and $F002) = $1000 then WritePaging1FFD(Value)
          else if (Port and $C002) = $4000 then WritePaging7FFD(Value);
        end
        else if (Port and $8002) = 0 then
          WritePaging7FFD(Value);
      end;
    mkPlus3:
      begin
        if (Port and $C002) = $4000 then
        begin
          if (FPort7FFD and $20) = 0 then WritePaging7FFD(Value);
        end
        else if (Port and $F002) = $1000 then
        begin
          if (FPort7FFD and $20) = 0 then WritePaging1FFD(Value);
        end
        else if FInfo.HasFDC and ((Port and $F002) = $3000) then
        begin
          FFDC.SetTime(FrameStartT + U(T));
          FFDC.WriteData(Value);
        end;
      end;
  end;

  if HasAY then
  begin
    if (Port and $C002) = $C000 then
    begin
      if TurboSound and (Value >= $FE) then
        FAYChip := (not Value) and 1    // $FF: first chip, $FE: second
      else
        ActiveAY.SelectRegister(Value);
    end
    else if (Port and $C002) = $8000 then
    begin
      if ActiveAY.Selected < 16 then
        AddEvent(U(T), 1 + Ord(ActiveAY = FAY2), ActiveAY.Selected, Value);
      ActiveAY.WriteData(Value);
    end;
  end;

  IOContendPost(Port, T);
end;

{ Video }

{ ZX-Uno }

function TSpectrum.IsZXUno: Boolean;
begin
  Result := FInfo.Memory = mkZXUno;
end;

{ The ZX-Uno has ULAplus, the Timex modes and Radastan (its DEVCTRL2 can
  switch them off); other models as Settings say }
function TSpectrum.HasULAPlus: Boolean;
begin
  if IsZXUno then Result := (FZXReg[$0F] and 1) = 0 else Result := ULAPlusEnabled;
end;

function TSpectrum.HasTimex: Boolean;
begin
  if IsZXUno then Result := (FZXReg[$0F] and 2) = 0 else Result := TimexEnabled;
end;

function TSpectrum.HasRadastan: Boolean;
begin
  if IsZXUno then Result := (FZXReg[$0F] and 4) = 0 else Result := RadastanEnabled;
end;

procedure TSpectrum.SetDivOn(Value: Boolean);
begin
  // The ZX-Uno's own DivMMC follows its MASTERCONF register
  if not IsZXUno then FDivOn := Value;
end;

{ Loading a tape on the ZX-Uno: once its BIOS has started the ROM (it locks
  MASTERCONF) and ESXDOS has booted, LOAD "": in 48K mode at once; with a
  128K menu (128K, +2A, Derby...) its fourth entry, 48 BASIC, first }
procedure TSpectrum.ZXUnoAutoLoadStep;
var
  I: Integer;
begin
  if (FZXReg[0] and $80) = 0 then Exit;   // the BIOS is still running
  Inc(FUnoAutoLoad);
  if FUnoAutoLoad < 330 then Exit;
  FUnoAutoLoad := -1;
  if (FZXReg[$0E] and 4) = 0 then
  begin
    // 128K paging on: a 128K menu
    for I := 1 to 3 do
    begin
      AutoType(4, [KEY_CAPS, KEY_6]); AutoType(8, []);
    end;
    AutoType(4, [KEY_ENTER]);
    AutoType(150, []);
  end;
  AutoType(4, [KEY_J]); AutoType(8, []);
  AutoType(4, [KEY_SYM, KEY_P]); AutoType(8, []);
  AutoType(4, [KEY_SYM, KEY_P]); AutoType(8, []);
  AutoType(4, [KEY_ENTER]);
end;

{ The /INT line now: the ULA's interrupt at the start of the frame (the
  Timex port's bit 6 and the ZX-Uno's RASTERCTRL bit 2 can switch it off)
  or the ZX-Uno's raster interrupt }
function TSpectrum.IntActive: Boolean;
begin
  if IsZXUno then
  begin
    Result := (FCpu.T < FInfo.InterruptLength * FSpeed) and ((FZXReg[$0D] and 4) = 0) and
      not (HasTimex and ((FTimexPort and $40) <> 0));
    if not Result and ((FZXReg[$0D] and 2) <> 0) then Result := RasterIntActive;
  end
  else
    Result := (FCpu.T < FInfo.InterruptLength * FSpeed) and
      not (HasTimex and ((FTimexPort and $40) <> 0));
end;

{ ZX-Uno raster interrupt (RASTERLINE, bit 0 of RASTERCTRL the 9th bit):
  for line L (0 = the first line of the paper) it comes at the end of line
  L - 1, in its right border (pixels 256-319, 32 T-states); for line 0 at
  the end of the frame's last line }
function TSpectrum.RasterIntActive: Boolean;
var
  Line, Lines, VC, T: Integer;
begin
  Line := FZXReg[$0C] or ((FZXReg[$0D] and 1) shl 8);
  Lines := FInfo.FrameT div FInfo.LineT;
  if Line = 0 then VC := Lines - 1 else VC := Line - 1;
  Result := False;
  if VC >= Lines then Exit;
  T := (FInfo.PaperTopT + VC * FInfo.LineT + 128) mod FInfo.FrameT;
  Result := (U(FCpu.T) >= T) and (U(FCpu.T) < T + 32);
end;

function TSpectrum.ZXUnoRegister(Reg: Byte): Byte;
begin
  Result := FZXReg[Reg];
end;

procedure TSpectrum.SetZXUnoRegister(Reg, Value: Byte);
begin
  ZXUnoWriteReg(Reg, Value);
end;

procedure TSpectrum.DebugSetZXUnoReg(Reg, Value: Byte);
begin
  if Reg = 1 then Value := Value and (ZXUNO_PAGES - 1);
  FZXReg[Reg] := Value;
  UpdatePaging;
end;

{ The ZX-Uno's SPI flash, as its BIOS finds it: ROMS.ZX1 is the three
  pieces of the flash its BIOS writes when upgrading the ROMs (6000: ROM
  directory, order and active ROM; 0C000: ROM slots 0-18; 34C000: slots
  19-63), FIRMWARE.ZX1 the BIOS (at 8000) and esxDOS goes at 4000. The BIOS
  settings (7040) are the saved ones (ZXUnoBiosSettings) }

function TSpectrum.GetZXUnoBios: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to ZXUNO_CFG_SIZE - 1 do Result := Result + IntToHex(FZXUnoCfg[I], 2);
end;

{ '' = the defaults: the first ROM (the 48K), boot screen shown (quiet boot
  off), and the factory flash's 2 3 2 2 2 2 (keyboard issue, timing,
  contention, DivMMC, NMI, graphics: as each ROM says) }
procedure TSpectrum.SetZXUnoBios(const Value: string);
const
  DEFAULTS: array[0..9] of Byte = (0, 0, 1, 0, 2, 3, 2, 2, 2, 2);
var
  I, V: Integer;
begin
  FillChar(FZXUnoCfg, SizeOf(FZXUnoCfg), 0);
  if Length(Value) >= ZXUNO_CFG_SIZE * 2 then
    for I := 0 to ZXUNO_CFG_SIZE - 1 do
    begin
      V := StrToIntDef('$' + Copy(Value, I * 2 + 1, 2), 0);
      FZXUnoCfg[I] := V;
    end
  else
    for I := 0 to High(DEFAULTS) do FZXUnoCfg[I] := DEFAULTS[I];
  FZXUnoCfgChanged := False;
end;
procedure TSpectrum.LoadZXUnoFlash;

  procedure LoadPart(const FileName: string; Pos, Size, FlashAt: Integer);
  var
    F: TFileStream;
  begin
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      if F.Size <= Pos then Exit;
      F.Position := Pos;
      F.Read(FZXFlash[FlashAt], Min(Size, F.Size - Pos));
    finally
      F.Free;
    end;
  end;

var
  Firmware, Roms: string;
  I: Integer;
begin
  Firmware := ZXUnoFirmware;
  Roms := ZXUnoRoms;
  if not FileExists(Firmware) then
    raise Exception.CreateFmt('ZX-Uno BIOS not found: %s', [Firmware]);
  if not FileExists(Roms) then
    raise Exception.CreateFmt('ZX-Uno ROMs not found: %s', [Roms]);
  SetLength(FZXFlash, ZXUNO_FLASH_SIZE);
  FillChar(FZXFlash[0], ZXUNO_FLASH_SIZE, 0);
  for I := $7000 to $703F do FZXFlash[I] := $FF;
  LoadPart(Firmware, 0, $4000, $8000);
  LoadPart(Roms, 0, $1041, $6000);
  LoadPart(Roms, $1041, $4C000, $C000);
  LoadPart(Roms, $1041 + $4C000, $B4000, $34C000);
  // The BIOS settings: saved ones, or the defaults
  for I := 0 to ZXUNO_CFG_SIZE - 1 do FZXFlash[ZXUNO_CFG + I] := FZXUnoCfg[I];
  if (ZXUnoEsxdos <> '') and FileExists(ZXUnoEsxdos) then LoadPart(ZXUnoEsxdos, 0, $2000, $4000);
  Move(FZXFlash[$8000], FZXBoot, SizeOf(FZXBoot));
  FZXCustomOn := (ZXUnoCustomRom <> '') and FileExists(ZXUnoCustomRom);
  if FZXCustomOn then
  begin
    FillChar(FZXCustom, SizeOf(FZXCustom), $FF);
    with TFileStream.Create(ZXUnoCustomRom, fmOpenRead or fmShareDenyWrite) do
      try
        Read(FZXCustom, SizeOf(FZXCustom));
      finally
        Free;
      end;
  end;
end;

{ Power on (Hard) or reset. On power on the FPGA's boot loader copies the
  BIOS from the flash (8000) to SRAM page 8 and runs it as ROM 0, out of
  boot mode; the BIOS then reads the ROMs from the flash, sets the machine
  up through the registers and starts the chosen ROM }
procedure TSpectrum.ZXUnoBoot(Hard: Boolean);
var
  I: Integer;
begin
  if Hard then
  begin
    for I := 0 to ZXUNO_PAGES - 1 do FillChar(FRam[I], SizeOf(TBank), 0);
    FillChar(FZXReg, SizeOf(FZXReg), 0);
    if Length(FZXFlash) = ZXUNO_FLASH_SIZE then Move(FZXFlash[$8000], FRam[8], SizeOf(TBank));
    FZXReg[1] := 8;
    FZXReg[$0C] := 255;
    FZXReg[$0D] := 1;
    FSpiIndex := 0;
    FSpiStatus := 0;
    FCoreIdPos := 0;
    FZXCustomRun := False;
    FZXKbdBat := True;
  end;
  // Raster interrupt off, normal one on (on any reset)
  FZXReg[$0C] := $FF;
  FZXReg[$0D] := 1;
  FDivOn := (FZXReg[0] and 2) <> 0;
  Issue2 := (FZXReg[0] and 8) <> 0;
  SetZXUnoTiming;
end;

{ MASTERCONF bits 4 and 6: 48K, 128K or Pentagon timing }
procedure TSpectrum.SetZXUnoTiming;
var
  Mode, I: Integer;
  Src: TModelInfo;
begin
  Mode := ((FZXReg[0] shr 4) and 1) or ((FZXReg[0] shr 5) and 2);
  if Mode = 0 then Src := ModelInfo[sm48K] else Src := ModelInfo[sm128K];
  FInfo.ClockHz := Src.ClockHz;
  FInfo.FrameT := Src.FrameT;
  FInfo.LineT := Src.LineT;
  FInfo.PaperTopT := Src.PaperTopT;
  FInfo.ContentionStartT := Src.ContentionStartT;
  FInfo.ContentionPattern := Src.ContentionPattern;
  FInfo.InterruptLength := Src.InterruptLength;
  FInfo.IOContention := True;
  if Mode >= 2 then
  begin
    // Pentagon: 320 lines of 224 T-states, no contention
    FInfo.ClockHz := 3500000;
    FInfo.FrameT := 71680;
    FInfo.LineT := 224;
    FInfo.PaperTopT := 80 * 224;
    FInfo.InterruptLength := 32;
    FInfo.IOContention := False;
    for I := 0 to 7 do FInfo.ContentionPattern[I] := 0;
  end;
  BuildContention;
  FTape.ClockHz := FInfo.ClockHz;
  UpdateContend;
end;

procedure TSpectrum.ZXUnoWriteReg(Reg, Value: Byte);
var
  Old: Byte;
begin
  case Reg of
    0:
      begin
        // MASTERCONF: LOCK MODE1 DISCONT MODE0 I2KB DISNMI DIVEN BOOTM; once
        // locked BOOTM and LOCK stay (as in the core's new_memory.v)
        Old := FZXReg[0];
        if (Old and $80) <> 0 then Value := (Value and $7E) or (Old and $81);
        if ((Old and $80) = 0) and ((Value and $80) <> 0) and FZXCustomOn then
        begin
          // The BIOS starts its ROM: the custom one replaces it, as a 48K
          // (48K timing, 128K and +3 paging off, ROM 0 fixed)
          Move(FZXCustom, FRam[8], SizeOf(TBank));
          FZXCustomRun := True;
          FZXReg[$0E] := FZXReg[$0E] or $3C;
          UpdatePaging;
        end;
        if FZXCustomRun then Value := Value and not $50;
        FZXReg[0] := Value;
        if ((Old xor Value) and 1) <> 0 then UpdatePaging;
        if ((Old xor Value) and 2) <> 0 then FDivOn := (Value and 2) <> 0;
        Issue2 := (Value and 8) <> 0;
        if ((Old xor Value) and $50) <> 0 then SetZXUnoTiming;
        if ((Old xor Value) and $20) <> 0 then SetContentionOn((Value and $20) = 0);
      end;
    1:
      if (FZXReg[0] and 1) <> 0 then
      begin
        FZXReg[1] := Value and $7F;   // MASTERMAPPER: SRAM page at C000, boot mode only
        UpdatePaging;
      end;
    2: if (FZXReg[0] and $80) = 0 then SpiWrite(Value);   // FLASHSPI
    4:
      begin
        FZXReg[4] := Value;   // SCANCODE: a command to the keyboard
        FZXKbdBat := False;
      end;
    3:
      if (FZXReg[0] and $80) = 0 then
      begin
        // FLASHCS: 0 selects the flash, a new command follows
        FZXReg[3] := Value;
        if (Value and 1) = 0 then FSpiIndex := 0;
      end;
    $0B:
      begin
        // SCANDBLCTRL: bits 6-7 the CPU speed (3.5, 7, 14, 28 MHz)
        FZXReg[$0B] := Value;
        SetSpeed(1 shl ((Value shr 6) and 3));
      end;
    $0E:
      begin
        if FZXCustomRun then Value := Value or $3C;
        FZXReg[$0E] := Value;   // DEVCONTROL: paging, ROM and AY switches
        UpdatePaging;
      end;
    $0F, $40:
      begin
        RenderUpTo(U(FCpu.T));
        FZXReg[Reg] := Value;
      end;
  else
    FZXReg[Reg] := Value;
  end;
end;

function TSpectrum.ZXUnoReadReg(Reg: Byte): Byte;
const
  CORE_ID = 'pzx-ZXUno';
begin
  case Reg of
    2: if (FZXReg[0] and $80) <> 0 then Result := $FF else Result := SpiRead;
    // SCANCODE: after power on a PS/2 keyboard sends AA (self-test passed),
    // which the BIOS reads first (with 0 it waits five times longer on its
    // boot screen); then nothing, until the BIOS talks to the keyboard
    4: if FZXKbdBat then Result := $AA else Result := 0;
    5: Result := 0;   // KEYBSTAT: no keys from a PS/2 keyboard
    $0D: Result := (FZXReg[$0D] and 7) or (Ord(((FZXReg[$0D] and 2) <> 0) and RasterIntActive) shl 7);
    $FF:
      begin
        // COREID: a text, ended with 0
        if FCoreIdPos >= Length(CORE_ID) then
        begin
          FCoreIdPos := 0;
          Result := 0;
        end
        else
        begin
          Inc(FCoreIdPos);
          Result := Ord(CORE_ID[FCoreIdPos]);
        end;
      end;
  else
    Result := FZXReg[Reg];
  end;
end;

{ SPI flash commands: 03 read (13 with a 4-byte address), 05 status, 9F
  JEDEC id, 06/04 write enable/disable, 02 page program, 20 sector erase.
  Writes change the flash in memory only }
procedure TSpectrum.SpiWrite(Value: Byte);
var
  I, A: Integer;
begin
  FSpiBus[FSpiIndex] := Value;
  if FSpiIndex < 7 then Inc(FSpiIndex);
  case FSpiBus[0] of
    $03:
      if FSpiIndex = 4 then
      begin
        FSpiAddr := (FSpiBus[1] shl 16) or (FSpiBus[2] shl 8) or FSpiBus[3];
        FSpiNext := Value;   // the first byte read is this one: the BIOS skips it
      end;
    $13:
      if FSpiIndex = 5 then
      begin
        FSpiAddr := (FSpiBus[2] shl 16) or (FSpiBus[3] shl 8) or FSpiBus[4] or (FSpiBus[1] shl 24);
        FSpiNext := Value;
      end;
    $06: FSpiStatus := FSpiStatus or 2;
    $04: FSpiStatus := FSpiStatus and not 2;
    $02:
      begin
        if FSpiIndex = 1 then
        begin
          if (FSpiStatus and 2) = 0 then FSpiIndex := 0;
          FSpiStatus := FSpiStatus and not 2;
        end
        else if FSpiIndex = 4 then
          FSpiAddr := (FSpiBus[1] shl 16) or (FSpiBus[2] shl 8) or FSpiBus[3]
        else if FSpiIndex = 5 then
        begin
          A := FSpiAddr and (ZXUNO_FLASH_SIZE - 1);
          FZXFlash[A] := Value;
          // The BIOS saving its settings: remember them
          if (A >= ZXUNO_CFG) and (A < ZXUNO_CFG + ZXUNO_CFG_SIZE) then
          begin
            FZXUnoCfg[A - ZXUNO_CFG] := Value;
            FZXUnoCfgChanged := True;
          end;
          Inc(FSpiAddr);
          FSpiIndex := 4;
        end;
      end;
    $20:
      begin
        if FSpiIndex = 1 then
        begin
          if (FSpiStatus and 2) = 0 then FSpiIndex := 0;
          FSpiStatus := FSpiStatus and not 2;
        end
        else if FSpiIndex = 4 then
        begin
          A := ((FSpiBus[1] shl 16) or (FSpiBus[2] shl 8) or FSpiBus[3]) and (ZXUNO_FLASH_SIZE - 1) and not $FFF;
          for I := 0 to $FFF do FZXFlash[A + I] := $FF;
        end;
      end;
  end;
end;

function TSpectrum.SpiRead: Byte;
begin
  case FSpiBus[0] of
    $03, $13:
      begin
        Result := FSpiNext;
        if Length(FZXFlash) = ZXUNO_FLASH_SIZE then
          FSpiNext := FZXFlash[FSpiAddr and (ZXUNO_FLASH_SIZE - 1)]
        else
          FSpiNext := $FF;
        Inc(FSpiAddr);
      end;
    $05: Result := FSpiStatus;
    $9F: Result := $16;   // 4 MB
  else
    Result := 0;
  end;
end;

function TSpectrum.RadastanOn: Boolean;
begin
  Result := HasRadastan and (((FULAPlusMode and 2) <> 0) or ((FZXReg[$40] and 3) = 3));
end;

function TSpectrum.ULAPlusOn: Boolean;
begin
  Result := HasULAPlus and ((FULAPlusMode and 1) <> 0);
end;

{ ULAplus colours are GGGRRRBB; the third blue bit is the OR of the other two }
procedure TSpectrum.SetULAPlusEntry(Index, Value: Byte);

  function Expand(V: Integer): LongWord;
  begin
    Result := (V shl 5) or (V shl 2) or (V shr 1);
  end;

var
  B: Integer;
begin
  FULAPlusPal[Index] := Value;
  B := Value and 3;
  B := (B shl 1) or Ord(B <> 0);
  FULAPlusRGB[Index] := $FF000000 or (Expand((Value shr 2) and 7) shl 16) or
    (Expand(Value shr 5) shl 8) or Expand(B);
end;

{ One 8-pixel cell of the frame (16 frame buffer pixels: each pixel twice,
  except in Timex hi-res) }
procedure TSpectrum.RenderCell(Line, Cell: Integer);
var
  P: PLongWord;
  FrameLine, PaperLine, Col, Bit, K, Clut, Base, Addr: Integer;
  Pixels, Pixels2, Attr, B: Byte;
  Ink, Paper, C: LongWord;
  Radas, Plus, HiRes, HiColour: Boolean;
begin
  P := @FFrameBuffer[Line * FB_WIDTH + Cell * 16];
  PaperLine := Line - BORDER_TOP;
  Col := Cell - BORDER_LEFT div 8;
  Radas := RadastanOn;
  Plus := ULAPlusOn;
  HiRes := HasTimex and ((FTimexPort and 4) <> 0);
  HiColour := HasTimex and not HiRes and ((FTimexPort and 2) <> 0);
  if HiRes then
  begin
    // Ink from bits 3-5, paper its complement (bright)
    Ink := Palette[8 + ((FTimexPort shr 3) and 7)];
    Paper := Palette[8 + 7 - ((FTimexPort shr 3) and 7)];
  end;
  if (PaperLine < 0) or (PaperLine >= 192) or (Col < 0) or (Col >= 32) then
  begin
    if Radas then C := FULAPlusRGB[FBorder]
    else if Plus then C := FULAPlusRGB[8 + FBorder]
    else if HiRes then C := Paper
    else C := Palette[FBorder];
    for Bit := 0 to 15 do P[Bit] := C;
    Exit;
  end;
  FrameLine := PaperLine;
  if HasTimex and ((FTimexPort and 1) <> 0) then Base := $2000 else Base := 0;
  if Radas then
  begin
    // 128x96, 4 bits per pixel, 64 bytes per line; each pixel 2x2
    for K := 0 to 1 do
    begin
      B := FRam[FScreenBank][Base + (FrameLine shr 1) * 64 + Col * 2 + K];
      C := FULAPlusRGB[B shr 4];
      for Bit := 0 to 3 do P[K * 8 + Bit] := C;
      C := FULAPlusRGB[B and 15];
      for Bit := 4 to 7 do P[K * 8 + Bit] := C;
    end;
    Exit;
  end;
  Addr := ((FrameLine and $C0) shl 5) or ((FrameLine and 7) shl 8) or ((FrameLine and $38) shl 2) or Col;
  if HiRes then
  begin
    // 512x192: columns alternate between the two screens
    Pixels := FRam[FScreenBank][Addr];
    Pixels2 := FRam[FScreenBank][$2000 + Addr];
    for Bit := 0 to 7 do
    begin
      if (Pixels and ($80 shr Bit)) <> 0 then P[Bit] := Ink else P[Bit] := Paper;
      if (Pixels2 and ($80 shr Bit)) <> 0 then P[8 + Bit] := Ink else P[8 + Bit] := Paper;
    end;
    Exit;
  end;
  if HiColour then
  begin
    // An attribute for every 8x1 cell, laid out like the bitmap, at 6000
    Pixels := FRam[FScreenBank][Addr];
    Attr := FRam[FScreenBank][$2000 + Addr];
  end
  else
  begin
    Pixels := FRam[FScreenBank][Base + Addr];
    Attr := FRam[FScreenBank][Base + $1800 + (FrameLine shr 3) * 32 + Col];
    if FSnowPix[FrameLine * 32 + Col] >= 0 then
    begin
      Pixels := FSnowPix[FrameLine * 32 + Col];
      FSnowPix[FrameLine * 32 + Col] := -1;
    end;
    if FSnowAttr[FrameLine * 32 + Col] >= 0 then
    begin
      Attr := FSnowAttr[FrameLine * 32 + Col];
      FSnowAttr[FrameLine * 32 + Col] := -1;
    end;
  end;
  if Plus then
  begin
    // FLASH and BRIGHT choose one of four 16-colour palettes: 8 inks, 8 papers
    Clut := (Attr shr 6) * 16;
    Ink := FULAPlusRGB[Clut + (Attr and 7)];
    Paper := FULAPlusRGB[Clut + 8 + ((Attr shr 3) and 7)];
  end
  else
  begin
    Ink := Palette[(Attr and 7) or ((Attr shr 3) and 8)];
    Paper := Palette[(Attr shr 3) and 15];
    if FFlashOn and ((Attr and $80) <> 0) then
    begin
      C := Ink; Ink := Paper; Paper := C;
    end;
  end;
  for Bit := 0 to 7 do
  begin
    if (Pixels and ($80 shr Bit)) <> 0 then C := Ink else C := Paper;
    P[Bit * 2] := C;
    P[Bit * 2 + 1] := C;
  end;
end;

procedure TSpectrum.RenderUpTo(T: Integer);
var
  CellT: Integer;
begin
  while FRenderLine < SCREEN_HEIGHT do
  begin
    // T-state at which this 8-pixel cell is displayed
    CellT := FInfo.PaperTopT + (FRenderLine - BORDER_TOP) * FInfo.LineT - BORDER_LEFT div 2 +
      FRenderCell * 4;
    if CellT > T then Exit;
    RenderCell(FRenderLine, FRenderCell);
    Inc(FRenderCell);
    if FRenderCell >= SCREEN_WIDTH div 8 then
    begin
      FRenderCell := 0;
      Inc(FRenderLine);
    end;
  end;
end;

procedure TSpectrum.RestartRender;
begin
  FRenderLine := 0;
  FRenderCell := 0;
end;

procedure TSpectrum.CopyFrameBuffer(Dest: PLongWord);
begin
  Move(FFrameBuffer[0], Dest^, FB_WIDTH * SCREEN_HEIGHT * SizeOf(LongWord));
end;

{ Audio }

procedure TSpectrum.AddEvent(T: Integer; Kind, Reg, Value: Byte);
begin
  if FEventCount >= Length(FEvents) then SetLength(FEvents, Length(FEvents) * 2);
  FEvents[FEventCount].T := T;
  FEvents[FEventCount].Kind := Kind;
  FEvents[FEventCount].Reg := Reg;
  FEvents[FEventCount].Value := Value;
  Inc(FEventCount);
end;

procedure TSpectrum.UpdateBeeper(T: Integer);
var
  Level: Byte;
begin
  // Encode EAR (bit 4), MIC (bit 3) and tape input into one level byte
  Level := (FUlaOut shr 3) and 3;
  if FTape.Playing and FTape.Level then Level := Level or 4;
  AddEvent(T, 0, 0, Level);
end;

procedure TSpectrum.TapeEdge(T: Integer; Level: Boolean);
begin
  UpdateBeeper(T);
end;

function BeeperValue(Level: Byte): Single; inline;
begin
  Result := 0;
  if (Level and 2) <> 0 then Result := Result + 0.75;   // EAR
  if (Level and 1) <> 0 then Result := Result + 0.08;   // MIC
  if (Level and 4) <> 0 then Result := Result + 0.25;   // tape
end;

procedure TSpectrum.ApplyEvent(Index: Integer);
begin
  case FEvents[Index].Kind of
    0: FBeeperLevel := FEvents[Index].Value;
    1: FAY.WriteRegister(FEvents[Index].Reg, FEvents[Index].Value);
    2: FAY2.WriteRegister(FEvents[Index].Reg, FEvents[Index].Value);
  end;
end;

procedure TSpectrum.GenerateAudio;
var
  TPerSample, Pos, EndT, NextT, Acc: Double;
  EvIndex, Ch, TickCount, K: Integer;
  Drive, Spinning, Reading: Boolean;
  Clicks: TInt64DynArray;
  ClickLen, Dt: Int64;
  Floppy, Rnd: Single;
  TickA, TickB, TickC, A, B, C, A2, B2, C2, L, R, AYGain: Single;
  Two: Boolean;
  Mix: array[0..1] of Single;
begin
  TPerSample := FInfo.ClockHz / SAMPLE_RATE;
  Two := TurboSound and HasAY;
  // Floppy drive noise: only with the drive at real speed
  Drive := FloppyNoise and FInfo.HasFDC and FFDC.Timed and
    ((FFDC.Disk(0) <> nil) or (FFDC.Disk(1) <> nil));
  if Drive then
  begin
    ClickLen := FInfo.ClockHz div 250;          // a click lasts 4 ms
    Clicks := FFDC.StepTimes(FrameStartT - ClickLen, FrameStartT + FInfo.FrameT);
    Spinning := FFDC.Motor;
    Reading := FFDC.HeadActive;
  end;
  if Two then AYGain := 0.25 else AYGain := 0.35;
  FSampleCount := 0;
  EvIndex := 0;
  if Length(FSamples) < Trunc(FInfo.FrameT / TPerSample) + 2 then
    SetLength(FSamples, Trunc(FInfo.FrameT / TPerSample) + 2);

  while FSamplePos + TPerSample <= FInfo.FrameT do
  begin
    Pos := FSamplePos;
    EndT := FSamplePos + TPerSample;
    Acc := 0;
    A := 0; B := 0; C := 0;
    A2 := 0; B2 := 0; C2 := 0;
    TickCount := 0;
    // Walk a merged timeline of events and AY ticks across the sample period
    repeat
      while (EvIndex < FEventCount) and (FEvents[EvIndex].T <= Pos) do
      begin
        ApplyEvent(EvIndex);
        Inc(EvIndex);
      end;
      if HasAY then
        while FAYTickT <= Pos do
        begin
          FAY.Tick(TickA, TickB, TickC);
          A := A + TickA; B := B + TickB; C := C + TickC;
          if Two then
          begin
            FAY2.Tick(TickA, TickB, TickC);
            A2 := A2 + TickA; B2 := B2 + TickB; C2 := C2 + TickC;
          end;
          Inc(TickCount);
          Inc(FAYTickT, 16);
        end;
      NextT := EndT;
      if (EvIndex < FEventCount) and (FEvents[EvIndex].T < NextT) then NextT := FEvents[EvIndex].T;
      if HasAY and (FAYTickT < NextT) then NextT := FAYTickT;
      Acc := Acc + BeeperValue(FBeeperLevel) * (NextT - Pos);
      Pos := NextT;
    until Pos >= EndT;
    Acc := Acc / TPerSample;

    if TickCount > 0 then
    begin
      FAYLevels[0] := A / TickCount;
      FAYLevels[1] := B / TickCount;
      FAYLevels[2] := C / TickCount;
      FAY2Levels[0] := A2 / TickCount;
      FAY2Levels[1] := B2 / TickCount;
      FAY2Levels[2] := C2 / TickCount;
    end;
    if not HasAY then
    begin
      FAYLevels[0] := 0; FAYLevels[1] := 0; FAYLevels[2] := 0;
    end;
    if not Two then
    begin
      FAY2Levels[0] := 0; FAY2Levels[1] := 0; FAY2Levels[2] := 0;
    end;
    // ABC stereo
    L := Acc * 0.5 + (FAYLevels[0] * 0.75 + FAYLevels[1] * 0.5 + FAYLevels[2] * 0.25 +
      FAY2Levels[0] * 0.75 + FAY2Levels[1] * 0.5 + FAY2Levels[2] * 0.25) * AYGain;
    R := Acc * 0.5 + (FAYLevels[2] * 0.75 + FAYLevels[1] * 0.5 + FAYLevels[0] * 0.25 +
      FAY2Levels[2] * 0.75 + FAY2Levels[1] * 0.5 + FAY2Levels[0] * 0.25) * AYGain;
    if Drive then
    begin
      Floppy := 0;
      if Spinning then
      begin
        // Motor: a low hum with a slow wobble, like the belt-driven 3" drive
        FMotorPhase := FMotorPhase + 2 * Pi * 95 / SAMPLE_RATE;
        if FMotorPhase > 2 * Pi then FMotorPhase := FMotorPhase - 2 * Pi;
        Floppy := Floppy + (0.018 * Sin(FMotorPhase) + 0.008 * Sin(3 * FMotorPhase));
      end;
      if Reading or Spinning then
      begin
        FNoiseSeed := FNoiseSeed * 1103515245 + 12345;
        Rnd := ((FNoiseSeed shr 16) and $7FFF) / 16384 - 1;
        FNoiseLP := FNoiseLP * 0.7 + Rnd * 0.3;
        // The head on the disk: a soft scratch while reading or writing
        if Reading then Floppy := Floppy + 0.05 * FNoiseLP
        else Floppy := Floppy + 0.006 * FNoiseLP;
      end;
      // Head steps: a sharp click each
      for K := 0 to High(Clicks) do
      begin
        Dt := FrameStartT + Round(Pos) - Clicks[K];
        if (Dt >= 0) and (Dt < ClickLen) then
          Floppy := Floppy + 0.45 * Exp(-Dt / (ClickLen * 0.12)) *
            Sin(2 * Pi * 1300 * Dt / FInfo.ClockHz);
      end;
      L := L + Floppy;
      R := R + Floppy;
    end;
    // DC blocking high-pass
    Mix[0] := L; Mix[1] := R;
    for Ch := 0 to 1 do
    begin
      FDCPrevOut[Ch] := Mix[Ch] - FDCPrevIn[Ch] + 0.995 * FDCPrevOut[Ch];
      FDCPrevIn[Ch] := Mix[Ch];
    end;
    if FMuted then
    begin
      FSamples[FSampleCount].L := 0;
      FSamples[FSampleCount].R := 0;
    end
    else
    begin
      FSamples[FSampleCount].L := EnsureRange(Round(FDCPrevOut[0] * FVolume * 32767), -32768, 32767);
      FSamples[FSampleCount].R := EnsureRange(Round(FDCPrevOut[1] * FVolume * 32767), -32768, 32767);
    end;
    Inc(FSampleCount);
    FSamplePos := EndT;
  end;

  // Events after the last whole sample still take effect
  while EvIndex < FEventCount do
  begin
    ApplyEvent(EvIndex);
    Inc(EvIndex);
  end;
  FEventCount := 0;
  FSamplePos := FSamplePos - FInfo.FrameT;
  Dec(FAYTickT, FInfo.FrameT);
end;

function TSpectrum.Samples: Pointer;
begin
  Result := @FSamples[0];
end;

{ Tape traps }

procedure TSpectrum.TapeTrap;
var
  Block: TTapeBlock;
  Len, N, I: Integer;
  Parity: Byte;
  Ok, Loading: Boolean;
  Addr: Word;
begin
  Block := FTape.TakeBlockForTrap;
  if Block = nil then Exit;
  Ok := False;
  Len := FCpu.DE.W;
  N := 0;
  if (Length(Block.Data) > 0) and (Block.Data[0] = FCpu.A_) then
  begin
    Loading := (FCpu.F_ and FLAG_C) <> 0;
    Parity := Block.Data[0];
    N := Min(Len, Length(Block.Data) - 1);
    Ok := True;
    for I := 0 to N - 1 do
    begin
      Addr := Word(FCpu.IX.W + I);
      Parity := Parity xor Block.Data[I + 1];
      if Loading then
        WriteMem(Addr, Block.Data[I + 1], FCpu.T)
      else if Peek(Addr) <> Block.Data[I + 1] then
      begin
        Ok := False;
        N := I;
        Break;
      end;
    end;
    if Ok then
      Ok := (N = Len) and (Length(Block.Data) >= Len + 2) and (Block.Data[Len + 1] = Parity);
  end;
  FCpu.IX.W := Word(FCpu.IX.W + N);
  FCpu.DE.W := Word(FCpu.DE.W - N);
  if Ok then
    FCpu.F := FCpu.F or FLAG_C
  else
    FCpu.F := FCpu.F and not FLAG_C;
  // Return through the RET at the end of LD-BYTES
  FCpu.PC.W := $05E2;
end;

{ SA-BYTES (04C2): A = flag, IX = start, DE = length. Store the block on the
  tape and continue at SA/LD-RET, which restores the border and returns. }
procedure TSpectrum.TapeSaveTrap;
var
  Data: TBytes;
  I: Integer;
  Parity: Byte;
begin
  SetLength(Data, FCpu.DE.W + 2);
  Data[0] := FCpu.A;
  Parity := FCpu.A;
  for I := 0 to FCpu.DE.W - 1 do
  begin
    Data[I + 1] := Peek(Word(FCpu.IX.W + I));
    Parity := Parity xor Data[I + 1];
  end;
  Data[High(Data)] := Parity;
  FTape.AddBlock(Data);
  FCpu.IX.W := Word(FCpu.IX.W + FCpu.DE.W);
  FCpu.DE.W := 0;
  FCpu.F := FCpu.F or FLAG_C;
  FCpu.PC.W := $053F;
end;

procedure TSpectrum.CheckTraps;
begin
  if not BasicRomPaged then Exit;
  if FDivOn and FDiv.Active then Exit;   // the DivMMC firmware is running there
  case FCpu.PC.W of
    $04C2:
      if SaveToTape then TapeSaveTrap;
    $056C:
      if FastLoad and not FTape.Playing and (FTape.Current < FTape.Count) then
        TapeTrap;
    $0556:
      if not FastLoad and AutoPlayTape and not FTape.Playing and (FTape.Current < FTape.Count) then
        FTape.Play(U(FCpu.T));
  end;
end;

{ Automatic typing }

function TSpectrum.KeyRow(Row: Integer): Byte;
begin
  Result := Keyboard[Row];
  if FAutoKeyPos < Length(FAutoKeys) then
    Result := Result and FAutoKeys[FAutoKeyPos].Rows[Row];
end;

procedure TSpectrum.AutoType(Frames: Integer; const Keys: array of Integer);
var
  N, I: Integer;
begin
  N := Length(FAutoKeys);
  SetLength(FAutoKeys, N + 1);
  FAutoKeys[N].Frames := Frames;
  FillChar(FAutoKeys[N].Rows, 8, $FF);
  for I := 0 to High(Keys) do
    FAutoKeys[N].Rows[Keys[I] div 5] := FAutoKeys[N].Rows[Keys[I] div 5] and not (1 shl (Keys[I] mod 5));
end;

procedure TSpectrum.CancelAutoType;
begin
  FAutoKeys := nil;
  FAutoKeyPos := 0;
  FAutoKeyFrames := 0;
end;

function TSpectrum.AutoTyping: Boolean;
begin
  Result := FAutoKeyPos < Length(FAutoKeys);
end;

function TSpectrum.TypeText(const Text: string; out Error: string): Boolean;
const
  // Characters typed with SYMBOL SHIFT and the key that gives them
  SYMBOLS = '!@#$%&''()_<>;"=+-^:?/*,.';
  SYMBOL_KEYS: array[1..Length(SYMBOLS)] of Integer = (
    KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_R, KEY_T,
    KEY_O, KEY_P, KEY_L, KEY_K, KEY_J, KEY_H, KEY_Z, KEY_C, KEY_V, KEY_B, KEY_N, KEY_M);
  LETTER_KEYS: array['A'..'Z'] of Integer = (
    KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I, KEY_J, KEY_K, KEY_L, KEY_M,
    KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R, KEY_S, KEY_T, KEY_U, KEY_V, KEY_W, KEY_X, KEY_Y, KEY_Z);
  DIGIT_KEYS: array['0'..'9'] of Integer = (
    KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9);
var
  I, P: Integer;
  Ch: Char;

  { Press for 4 frames, then release for 8: the ROM ignores a repeated key
    until it has been up for 5 frames }
  procedure Tap(const Keys: array of Integer);
  begin
    AutoType(4, Keys);
    AutoType(8, []);
  end;

begin
  Result := False;
  Error := '';
  I := 1;
  while I <= Length(Text) do
  begin
    Ch := Text[I];
    if (Ch = '\') and (I < Length(Text)) then
    begin
      Inc(I);
      case Text[I] of
        'n', 'N': Tap([KEY_ENTER]);
        'w', 'W': AutoType(50, []);
      else
        Error := 'unknown escape \' + Text[I];
        Exit;
      end;
    end
    else if Ch in ['a'..'z'] then Tap([LETTER_KEYS[UpCase(Ch)]])
    else if Ch in ['A'..'Z'] then Tap([LETTER_KEYS[Ch]])
    else if Ch in ['0'..'9'] then Tap([DIGIT_KEYS[Ch]])
    else if Ch = '~' then AutoType(25, [])     // half a second
    else if Ch = ' ' then Tap([KEY_SPACE])
    else if (Ch = #13) or (Ch = #10) then Tap([KEY_ENTER])
    else
    begin
      P := Pos(Ch, SYMBOLS);
      if P = 0 then
      begin
        Error := 'can''t type "' + Ch + '"';
        Exit;
      end;
      Tap([KEY_SYM, SYMBOL_KEYS[P]]);
    end;
    Inc(I);
  end;
  Result := True;
end;

procedure TSpectrum.AdvanceAutoKeys;
begin
  if FAutoKeyPos >= Length(FAutoKeys) then Exit;
  Inc(FAutoKeyFrames);
  if FAutoKeyFrames >= FAutoKeys[FAutoKeyPos].Frames then
  begin
    FAutoKeyFrames := 0;
    Inc(FAutoKeyPos);
    if FAutoKeyPos >= Length(FAutoKeys) then CancelAutoType;
  end;
end;

procedure TSpectrum.AutoLoad;
begin
  Reset(True);
  FTape.Rewind;
  CancelAutoType;
  if IsZXUno then
    // Its BIOS chooses the ROM: decided once it has started it
    FUnoAutoLoad := 0
  else if FInfo.Memory = mk48K then
  begin
    // LOAD "" ENTER: J, SYMBOL+P twice, ENTER. The ROM ignores a repeated
    // key until it has been released for 5 frames. The DivMMC firmware
    // takes a while to boot first.
    if FDivOn then AutoType(330, []) else AutoType(90, []);
    AutoType(4, [KEY_J]); AutoType(8, []);
    AutoType(4, [KEY_SYM, KEY_P]); AutoType(8, []);
    AutoType(4, [KEY_SYM, KEY_P]); AutoType(8, []);
    AutoType(4, [KEY_ENTER]);
  end
  else
  begin
    // Select the first menu entry (Tape Loader / Loader). The ZX-Uno's
    // BIOS starts its 128K ROM (and ESXDOS) first
    if FDivOn then AutoType(330, []) else AutoType(80, []);
    AutoType(4, [KEY_ENTER]);
  end;
end;

{ Frame execution }

{ Breakpoints }

function TSpectrum.GetBreakpoint(Addr: Word): Byte;
begin
  Result := FBreakFlags[Addr];
end;

procedure TSpectrum.SetBreakpoint(Addr: Word; Flags: Byte);
begin
  if (Flags = 0) and (Length(FBreakConds) > 0) then FreeAndNil(FBreakConds[Addr]);
  if (FBreakFlags[Addr] and (BP_READ or BP_WRITE)) <> 0 then Dec(FMemBreakpoints);
  FBreakFlags[Addr] := Flags;
  if (Flags and (BP_READ or BP_WRITE)) <> 0 then Inc(FMemBreakpoints);
end;

procedure TSpectrum.ClearBreakpoints;
var
  I: Integer;
begin
  FillChar(FBreakFlags, SizeOf(FBreakFlags), 0);
  FMemBreakpoints := 0;
  for I := 0 to High(FBreakConds) do FreeAndNil(FBreakConds[I]);
  FillChar(FPortBreakFlags, SizeOf(FPortBreakFlags), 0);
  FPortBreakpoints := 0;
  for I := 0 to High(FPortBreakConds) do FreeAndNil(FPortBreakConds[I]);
end;

function TSpectrum.GetPortBreakpoint(Port: Word): Byte;
begin
  Result := FPortBreakFlags[Port];
end;

procedure TSpectrum.SetPortBreakpoint(Port: Word; Flags: Byte);
begin
  Flags := Flags and (BP_READ or BP_WRITE or BP_DISABLED);
  if (Flags and (BP_READ or BP_WRITE)) = 0 then
  begin
    Flags := 0;
    if Length(FPortBreakConds) > 0 then FreeAndNil(FPortBreakConds[Port]);
  end;
  if FPortBreakFlags[Port] <> 0 then Dec(FPortBreakpoints);
  FPortBreakFlags[Port] := Flags;
  if Flags <> 0 then Inc(FPortBreakpoints);
end;

function TSpectrum.SetPortBreakCondition(Port: Word; const Text: string; out Error: string): Boolean;
var
  Cond: TBreakCondition;
begin
  Error := '';
  Cond := nil;
  if Trim(Text) <> '' then
  begin
    Cond := CompileCondition(Text, Error);
    if Cond = nil then Exit(False);
  end;
  if Length(FPortBreakConds) = 0 then SetLength(FPortBreakConds, $10000);
  FPortBreakConds[Port].Free;
  FPortBreakConds[Port] := Cond;
  Result := True;
end;

function TSpectrum.BreakHits(Addr: Word): Integer;
begin
  Result := -1;
  if (Length(FBreakConds) > 0) and (FBreakConds[Addr] <> nil) and FBreakConds[Addr].UsesHits then
    Result := FBreakConds[Addr].Hits;
end;

function TSpectrum.PortBreakHits(Port: Word): Integer;
begin
  Result := -1;
  if (Length(FPortBreakConds) > 0) and (FPortBreakConds[Port] <> nil) and
     FPortBreakConds[Port].UsesHits then
    Result := FPortBreakConds[Port].Hits;
end;

function TSpectrum.PortBreakCondition(Port: Word): string;
begin
  if (Length(FPortBreakConds) > 0) and (FPortBreakConds[Port] <> nil) then
    Result := FPortBreakConds[Port].Text
  else
    Result := '';
end;

{ A port breakpoint for this access (counting its T) }
function TSpectrum.PortBreakMatch(Port: Word; Write: Boolean): Boolean;
var
  Want: Byte;

  function Matches(Entry: Word): Boolean;
  begin
    Result := ((FPortBreakFlags[Entry] and (Want or BP_DISABLED)) = Want) and
      ((Length(FPortBreakConds) = 0) or (FPortBreakConds[Entry] = nil) or
       FPortBreakConds[Entry].Holds(FCpu));
  end;

begin
  if Write then Want := BP_WRITE else Want := BP_READ;
  Result := Matches(Port and $FF) or ((Port > $FF) and Matches(Port));
end;

procedure TSpectrum.CheckPortBreak(Port: Word; Write: Boolean);
begin
  // Normally the probe has already stopped before the instruction; this
  // catches the accesses it can't see in advance
  if (FPortBreakpoints = 0) or FSuppressBreaks then Exit;
  if PortBreakMatch(Port, Write) then
  begin
    FBreakHit := True;
    FBreakKind := bkPort;
    FBreakInstr := FInstrPC;
    if Write then
      FBreakReason := Format('Port write breakpoint: OUT to %.4X (instruction at %.4X)',
        [Port, FInstrPC])
    else
      FBreakReason := Format('Port read breakpoint: IN from %.4X (instruction at %.4X)',
        [Port, FInstrPC]);
  end;
end;

{ Run the next instruction on a copy of the CPU whose bus only records the
  addresses and ports used, and check them against the memory and port
  breakpoints, so the emulation stops before the instruction (PC on it). }
function TSpectrum.ProbeBreak: Boolean;
var
  Probe: TProbeBus;
  I: Integer;
  A: Word;
begin
  Result := False;
  Probe := TProbeBus(FProbeBus);
  Probe.Count := 0;
  FProbeCpu.CopyStateFrom(FCpu);
  FProbeCpu.Step;
  for I := 0 to Probe.Count - 1 do
  begin
    A := Probe.Accesses[I].Addr;
    case Probe.Accesses[I].Kind of
      0, 1:
        if (FMemBreakpoints > 0) and
           ((FBreakFlags[A] and (BP_READ shl Probe.Accesses[I].Kind or BP_DISABLED)) =
            BP_READ shl Probe.Accesses[I].Kind) and ConditionHolds(A) then
        begin
          FBreakKind := bkMemory;
          if Probe.Accesses[I].Kind = 0 then
            FBreakReason := Format('Read breakpoint at %.4X (instruction at %.4X)', [A, FCpu.PC.W])
          else
            FBreakReason := Format('Write breakpoint at %.4X (instruction at %.4X)', [A, FCpu.PC.W]);
          Result := True;
        end;
      2, 3:
        if (FPortBreakpoints > 0) and PortBreakMatch(A, Probe.Accesses[I].Kind = 3) then
        begin
          FBreakKind := bkPort;
          if Probe.Accesses[I].Kind = 3 then
            FBreakReason := Format('Port write breakpoint: OUT to %.4X (instruction at %.4X)',
              [A, FCpu.PC.W])
          else
            FBreakReason := Format('Port read breakpoint: IN from %.4X (instruction at %.4X)',
              [A, FCpu.PC.W]);
          Result := True;
        end;
    end;
    if Result then
    begin
      FBreakInstr := FCpu.PC.W;
      Exit;
    end;
  end;
end;

function TSpectrum.GetRecording: Boolean;
begin
  Result := FRecorder.Active;
end;

procedure TSpectrum.SetRecording(Value: Boolean);
begin
  if Value = FRecorder.Active then Exit;
  if Value then
  begin
    FTape.Stop;   // like a real recorder: REC with the tape moving forward
    FMicLevel := (FUlaOut and $18) <> 0;
    FRecorder.Start;
  end
  else
    FRecorder.Stop;
end;

function TSpectrum.ConditionHolds(Addr: Word): Boolean;
begin
  Result := (Length(FBreakConds) = 0) or (FBreakConds[Addr] = nil) or
    FBreakConds[Addr].Holds(FCpu);
end;

function TSpectrum.SetBreakCondition(Addr: Word; const Text: string; out Error: string): Boolean;
var
  Cond: TBreakCondition;
begin
  Error := '';
  Cond := nil;
  if Trim(Text) <> '' then
  begin
    Cond := CompileCondition(Text, Error);
    if Cond = nil then Exit(False);
  end;
  if Length(FBreakConds) = 0 then SetLength(FBreakConds, $10000);
  FBreakConds[Addr].Free;
  FBreakConds[Addr] := Cond;
  Result := True;
end;

function TSpectrum.BreakCondition(Addr: Word): string;
begin
  if (Length(FBreakConds) > 0) and (FBreakConds[Addr] <> nil) then
    Result := FBreakConds[Addr].Text
  else
    Result := '';
end;

procedure TSpectrum.LogPort(Port: Word; Value: Byte; Write: Boolean);
begin
  FPortLog[FPortLogPos].PC := FInstrPC;
  FPortLog[FPortLogPos].Port := Port;
  FPortLog[FPortLogPos].Value := Value;
  FPortLog[FPortLogPos].Write := Write;
  FPortLogPos := (FPortLogPos + 1) mod PORT_LOG_SIZE;
  if FPortLogCount < PORT_LOG_SIZE then Inc(FPortLogCount);
end;

function TSpectrum.PortLogCount: Integer;
begin
  Result := FPortLogCount;
end;

function TSpectrum.PortLog(Index: Integer): TPortAccess;
begin
  Result := FPortLog[(FPortLogPos - 1 - Index + PORT_LOG_SIZE * 2) mod PORT_LOG_SIZE];
end;

procedure TSpectrum.SkipBreakpointOnce;
begin
  FSkipBreakOnce := True;
  FSkipProbeOnce := FBreakKind in [bkMemory, bkPort];
end;

{ Frame execution }

{ One step of the frame loop: an NMI, an accepted interrupt, or one instruction. }
procedure TSpectrum.ExecuteOne;
begin
  if FTrackPrev then FPrevRegs := FCpu.GetRegs;
  if FNMIRequest then
  begin
    FNMIRequest := False;
    FCpu.NMI;
    Exit;
  end;
  if IntActive and FCpu.IFF1 and FCpu.Interrupt then Exit;
  if FCpu.PC.W < $4000 then CheckTraps;
  FInstrPC := FCpu.PC.W;
  FSuppressBreaks := FProbeCovered;
  FCpu.Step;
  FSuppressBreaks := False;
end;

procedure TSpectrum.FinishFrame;
begin
  if FUnoAutoLoad >= 0 then ZXUnoAutoLoadStep;
  RenderUpTo(MaxInt);
  FTape.AdvanceTo(FInfo.FrameT);
  GenerateAudio;

  if FRecorder.Active then FRecorder.Idle(FCpuTBase + FrameLength);
  Inc(FCpuTBase, FrameLength);
  Dec(FCpu.T, FrameLength);
  FTape.EndFrame(FInfo.FrameT);
  if FPendingSpeed <> FSpeed then
  begin
    // Keep the position within the frame when the clock changes
    FCpu.T := FCpu.T div FSpeed * FPendingSpeed;
    FSpeed := FPendingSpeed;
    UpdateContend;
  end;
  FFDC.Tick;
  FRenderLine := 0;
  FRenderCell := 0;
  Inc(FFrameCount);
  AdvanceAutoKeys;
  Inc(FFlashCounter);
  if FFlashCounter >= 16 then
  begin
    FFlashCounter := 0;
    FFlashOn := not FFlashOn;
  end;
end;

function TSpectrum.RunFrame: Boolean;
var
  PC: Word;
begin
  FBreakHit := False;
  FBreakKind := bkNone;
  while FCpu.T < FrameLength do
  begin
    PC := FCpu.PC.W;
    FProbeCovered := False;
    if FSkipBreakOnce then
    begin
      FSkipBreakOnce := False;
      // Resuming from a memory or port stop: run that instruction unchecked
      FProbeCovered := FSkipProbeOnce;
      FSkipProbeOnce := False;
      if not FProbeCovered and ((FMemBreakpoints > 0) or (FPortBreakpoints > 0)) and
         not FNMIRequest and not (IntActive and FCpu.IFF1 and not FCpu.EIJust) then
      begin
        FProbeCovered := True;
        if ProbeBreak then Exit(False);
      end;
    end
    else if ((FBreakFlags[PC] and (BP_EXEC or BP_DISABLED)) = BP_EXEC) and ConditionHolds(PC) then
    begin
      FBreakReason := Format('Breakpoint at %.4X', [PC]);
      FBreakKind := bkExec;
      FBreakInstr := PC;
      Exit(False);
    end
    else if PC = FTempBreak then
    begin
      FTempBreak := -1;
      FBreakReason := '';
      FBreakKind := bkRunTo;
      FBreakInstr := PC;
      Exit(False);
    end
    else if ((FMemBreakpoints > 0) or (FPortBreakpoints > 0)) and not FNMIRequest and
      not (IntActive and FCpu.IFF1 and not FCpu.EIJust) then
    begin
      // The next step runs this instruction (no interrupt first): look ahead
      FProbeCovered := True;
      if ProbeBreak then Exit(False);
    end;
    ExecuteOne;
    if FBreakHit then
    begin
      // Memory breakpoints stop after the instruction that touched memory
      if FCpu.T >= FrameLength then FinishFrame;
      Exit(False);
    end;
  end;
  FinishFrame;
  Result := True;
end;

procedure TSpectrum.StepInstruction;
begin
  FBreakHit := False;
  FBreakKind := bkNone;
  FSkipBreakOnce := False;
  ExecuteOne;
  if FCpu.T >= FrameLength then FinishFrame;
  // Show the picture up to the current beam position
  RenderUpTo(U(FCpu.T));
end;

end.
