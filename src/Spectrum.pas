{ Spectrum: the machine. Memory paging, ULA contention, I/O decoding,
  T-state accurate video, beeper/AY audio capture and frame execution for
  all supported models. }
unit Spectrum;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  SysUtils, Classes, Math, Types, Z80Core, Models, AY8912, Tape, FDC765, BreakExpr, DivMMC, Daad, Currah,
  Disasm, Amstrad, Sam, WD1772, SAA1099, DSK, SamdosFS, MsxMachine, C64, FloppySound;

const
  SCREEN_WIDTH = 352;
  SCREEN_HEIGHT = 288;
  { The frame buffer is twice as wide: every pixel twice, so the Timex
    512-pixel hi-res mode fits }
  FB_WIDTH = SCREEN_WIDTH * 2;
  BORDER_LEFT = 48;
  BORDER_TOP = 48;
  SAMPLE_RATE = 44100;

  PORT_LOG_SIZE = 50;  // port accesses remembered for the debugger

type
  TBank = array[0..$3FFF] of Byte;
  PBank = ^TBank;

  TAudioEvent = record
    T: Integer;
    Kind: Byte;     // 0 = beeper level, 1 = AY register write, 2 = second AY (TurboSound), 5 = SAA1099 write,
                    // 3 = the Next's DACs (Reg: which of A-D), 4 = the Next's third AY
    Reg: Byte;
    Value: Byte;
  end;

  { One port access, for the debugger }
  TPortAccess = record
    PC: Word;        // address of the instruction that did it
    Port: Word;
    Value: Byte;
    Write: Boolean;
    Step: LongWord;  // StepCount when it happened
  end;

  { Memory paging, for the debugger to show what an instruction changed }
  TPagingState = record
    Slots: array[0..3] of Integer;   // as SlotBank
    DivActive, DivMapped: Boolean;   // the DivMMC paged in; by automap
    CurrahPaged: Boolean;            // the Currah µSpeech's ROM paged in
    DivControl: Byte;                // its port E3
    UnoConf, UnoMapper: Byte;        // ZX-Uno MASTERCONF and MASTERMAPPER
  end;

  { What stopped the emulation }
  TBreakKind = (bkNone, bkExec, bkMemory, bkPort, bkRunTo, bkDaad);

  { Adventure Debugger: where to stop next. dsNext: at the next condact; dsOver:
    at the next one with SP at or above DaadSP (after a PROCESS returns) }
  TDaadStop = (dsNone, dsNext, dsOver);

const
  { ZX-Uno: 512K of SRAM in 16K pages (0-7 the RAM banks, 8-11 the ROM, 12
    the DivMMC firmware...) and a 4 MB SPI flash }
  ZXUNO_PAGES = 32;
  { RAM in 16K banks: 8 on the 128K models, the ZX-Uno's 512K of SRAM, the
    ZX Spectrum Next's 1792K (224 pages of 8K) }
  RAM_BANKS = 112;
  NEXT_PAGES = 224;
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
    Rows: array[0..10] of Byte;  // bits cleared for pressed keys (the CPC has 10 lines, the MSX 11)
  end;

  TMemoryAt = (maRam, maRom, maNone);

  { One breakpoint over First..Last: the flags and condition of each
    address (or port) in it are the same, and changing any changes all }
  TBreakRange = record
    First, Last: Word;
    Port: Boolean;
  end;

  { The whole machine as it was (CPU, all the RAM, paging, the DivMMC...),
    for the debugger's step back. Sound and the tape are not kept. }
  TMachineState = class
  public
    Model: TSpectrumModel;
    Cpu: TZ80;
    Ram: array of TBank;              // the banks the model has
    DivState: TDivState;
    NextReg: array[0..255] of Byte;
    NextSram: array of TBank;         // the Next's first 256K of SRAM
    NextBootOn: Boolean;
    MfNmi, MfOn, MfInvisible, DivNmiButton, NmiStackless: Boolean;
    CopperPC, CopperClk, CopperDue: Integer;
    CopperStopped, CopperRestarted: Boolean;
    NextSel, PortDFFD: Byte;
    NextMMU: array[0..7] of Byte;
    CurrahPaged: Boolean;
    CPCState: TBytes;                 // the Amstrad CPC's hardware (TAmstrad.SaveState)
    SamState: TBytes;                 // the SAM Coupe's ASIC and sound generator (SAMStateIO)
    C64State: TBytes;                 // the whole Commodore 64 (TC64.StateIO)
    Port7FFD, Port1FFD, Border, UlaOut, TimexPort, ULAPlusReg, ULAPlusMode, ZXUnoReg: Byte;
    ULAPlusPal: array[0..63] of Byte;
    ZXReg: array[0..255] of Byte;
    ScreenBank: Integer;
    FrameCount, CpuTBase: Int64;
    RenderLine, RenderCell, EventCount, AYTickT: Integer;
    SamplePos: Double;
    PrevRegs: TZ80Regs;
    PrevPaging: TPagingState;
    StepCount: LongWord;
    PortLog: array[0..PORT_LOG_SIZE - 1] of TPortAccess;
    PortLogPos, PortLogCount: Integer;
    destructor Destroy; override;
  end;

  TSpectrum = class(TZ80Bus)
  private
    FModel: TSpectrumModel;
    FInfo: TModelInfo;
    FCpu: TZ80;
    FAY: TAY8912;
    FAY2: TAY8912;                       // second chip (TurboSound)
    FAY3: TAY8912;                       // third chip (the Next)
    FAYChip: Integer;                    // chip selected by port $FFFD (TurboSound)
    FAY2Levels, FAY3Levels: array[0..2] of Single;
    FAYPan: array[0..2] of Byte;         // the Next: each chip's left (bit 1) and right (bit 0) output
    FFloppySound: TFloppySound;        // floppy drive noise
    FTape: TTape;
    { Auto play/stop: the Spectrum's demand for tape, from how often the EAR
      port is read (see TapeAuto) }
    FTapeReads: Integer;                   // reads of the EAR port this frame
    FDemandFrames, FQuietFrames: Integer;  // frames in a row with and without that many reads
    FLoadDemand: Boolean;                  // a load is under way
    FTapeHeld: Boolean;                    // the user stopped the tape, or a TZX block did: no auto play until a new load
    FLoadedSincePlay: Boolean;             // the tape has been playing while a load was under way
    FBlockStopSeen: Boolean;
    FLoadEnded: Boolean;                   // the ROM's LD-BYTES returned this frame
    FTapeEpoch: Integer;
    FFDC: TUPD765;
    FWD: TWD1772;                        // the SAM Coupe's floppy controller
    FRam: array[0..RAM_BANKS - 1] of TBank;   // 0-7 the RAM banks (32: ZX-Uno SRAM; 112: Next)
    FRom: array[0..3] of TBank;
    FNoMem: TBank;                       // unpopulated memory (16K): reads $FF
    FRomDir: string;
    FSlot: array[0..3] of PBank;
    FSlotBank: array[0..3] of Integer;   // RAM bank in slot, or -1 - ROM number
    FSlotContended: array[0..3] of Boolean;
    { What the CPU sees, in 8K pages: every memory access goes through
      these (filled from the 16K slots, or on the Next from its MMU) }
    FPage: array[0..7] of PByte;
    FPageRO: array[0..7] of Boolean;        // writes ignored (ROM, no memory)
    FPageScreen: array[0..7] of Boolean;    // the first 8K of the screen bank
    // ZX Spectrum Next
    FNextDir: string;                       // its distribution (specnext folder)
    FNextReg: array[0..255] of Byte;        // Next registers (port 243B selects, 253B data)
    FNextSel: Byte;
    FNextMMU: array[0..7] of Byte;          // 8K page per slot, 255 = ROM
    FPortDFFD: Byte;
    { The machine's own turbo, 1, 2, 4 or 8 (the Next's NR 07, the ZX-Uno's
      SCANDBLCTRL: 3.5 to 28 MHz), on top of the speed setting; 1 for the
      other models }
    FNextSpeed: Integer;
    FUserSpeed: Integer;                    // the speed setting
    FNextSpecial: Boolean;                  // +3 all-RAM paging in use
    { The first 256K of the Next's SRAM, in 16K banks: 0-3 the ROMs, 4 the
      DivMMC's ROM (and the Multiface's), 6-7 the alternate ROMs, 8-15 the
      DivMMC's RAM; the RAM pages (FRam) follow }
    FNextSram: array[0..15] of TBank;
    FNextBootRom: array[0..$1FFF] of Byte;  // the FPGA's boot ROM (loads TBBLUE.FW)
    FNextBootOn: Boolean;                   // the boot ROM is at 0000 (until NR 03 is written)
    FNextFirmware: Boolean;                 // boot through the firmware (else NextZXOS directly)
    FNextBootRomFile: string;
    FNextMachineId: Byte;                   // NR 00
    // Next video (NextVideo.inc)
    FNextPal: array[0..7, 0..255] of Word;  // palettes: 9-bit colour, bit 9 Layer 2 priority
    FNextPalRGB: array[0..7, 0..255] of LongWord;
    FNextPal44: Boolean;                    // NR 44: the first byte has been written
    FNextClip: array[0..3, 0..3] of Byte;   // Layer 2, sprites, ULA, tilemap: X1 X2 Y1 Y2
    FNextClipIdx: array[0..3] of Byte;
    FNextL2Port: Byte;                      // port 123B
    FNextL2Offset: Byte;                    // port 123B bank offset (bit 4 writes)
    FSprAttr: array[0..127, 0..4] of Byte;
    FSprPattern: array[0..$3FFF] of Byte;
    FSprIndex: Integer;                     // sprite whose attributes are written next
    FSprAttrIdx: Integer;                   // its attribute byte
    FSprPatAddr: Integer;                   // pattern memory address
    FSprStatus: Byte;                       // port 303B
    FNextLine: array[0..639] of LongWord;   // the line being composed
    FCopper: array[0..1023] of Word;
    FCopperAddr: Integer;                   // write address (bytes)
    FCopperPC: Integer;                     // instruction being run
    FCopperStopped: Boolean;
    FCopperClk: Integer;                    // its clock in the frame (4 per T-state)
    FCopperDue: Integer;                    // when it next has something to do (its clock)
    FCopperRestarted: Boolean;              // mode 11: restarted at 0,0 in this frame
    FCopperInRun: Boolean;                  // a MOVE of its own is writing a register
    FNextDrawnX: Integer;                   // frame buffer pixels of FRenderLine drawn
    // zxnDMA (NextDma.inc)
    FDmaQueue: array[0..7] of Integer;      // what the next bytes written are
    FDmaQueueLen: Integer;
    FDmaPortA, FDmaPortB, FDmaLength: Word;
    FDmaA, FDmaB, FDmaCount: Word;          // the counters
    FDmaAtoB, FDmaAIO, FDmaBIO, FDmaBurst, FDmaRestart, FDmaActive: Boolean;
    FDmaAMode, FDmaBMode, FDmaTimingA, FDmaTimingB: Integer;
    FDmaPrescaler: Integer;
    FDmaNextT: Int64;
    FDmaReadMask, FDmaReadIdx: Integer;
    FNextDac: array[0..3] of Byte;          // DACs A-D (128 = silence)
    FNextResetReq: Integer;                 // NR 02: 1 soft, 2 hard reset after the instruction
    // A .nex file kept open for its program (header bytes 140-141)
    FNexData: TBytes;
    FNexPos: Integer;
    FNexOpen: Boolean;
    FNexName: string;     // the .nex file's name, for programs that open it again
    FNexMap: array of Int64;                // where it is on the SD card (sector, count pairs)
    FNexMapPos: Integer;                    // DISK_FILEMAP: the next pair to give
    // The Next's SPI flash (port E7 bit 7 selects it, EB its data): where
    // the firmware keeps the extra cores; in memory only, made on first use
    FNextSpiCS: Byte;                       // port E7
    FNextFlash: array of Byte;
    FNextFlashCmd: array[0..7] of Byte;
    FNextFlashIdx, FNextFlashAddr, FNextFlashReads: Integer;
    FNextFlashWel: Boolean;                 // write enabled
    FForeignCore: Integer;
    // The Next's Multiface (multiface.vhd in the Next's FPGA sources)
    FMfNmi: Boolean;                        // its NMI is in progress (until RETN or its ports)
    FMfOn: Boolean;                         // its ROM and RAM paged in at 0000-3FFF
    FMfInvisible: Boolean;                  // its enable port doesn't page it in
    FNmiStackless: Boolean;                 // the next RETN returns to NR C2-C3
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
    FCPCIoT: Integer;                       // CPC: T-state of the I/O of the instruction being run (-1: by the CPU's count)
    FCPCIntShort: Boolean;                  // CPC: the last instruction lets an interrupt in a microsecond sooner
    FPortLog: array[0..PORT_LOG_SIZE - 1] of TPortAccess;
    FPortLogPos: Integer;                   // next entry to write
    FPortLogCount: Integer;
    FMemBreakpoints: Integer;               // number of read/write breakpoints
    FPortBreakFlags: array[0..$FFFF] of Byte;   // BP_READ (IN) / BP_WRITE (OUT) per port
    FPortBreakConds: array of TBreakCondition;
    FPortBreakpoints: Integer;
    FBreakRanges: array of TBreakRange;     // breakpoints over a range of addresses or ports
    FProbeBus: TZ80Bus;                     // dry run of the next instruction
    FProbeCpu: TZ80;
    FProbeCovered: Boolean;                 // the probe checked the instruction being run
    FSkipProbeOnce: Boolean;
    FSuppressBreaks: Boolean;               // no access checks during the probed instruction
    FDebugOut: Boolean;                     // an OUT of the debugger's: not logged, no port breakpoint
    FCpuTBase: Int64;                       // CPU T-states before this frame (tape recording)
    FRecorder: TTapeRecorder;
    FDiv: TDivMMC;
    FDivOn: Boolean;                        // DivMMC connected
    FCurrah: TCurrah;
    FCurrahOn: Boolean;                     // Currah µSpeech connected
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
    FPrevPaging: TPagingState;              // paging before the last instruction
    FStepCount: LongWord;                   // steps run (instructions, interrupts, NMIs)
    FAutoKeys: array of TAutoKeyStep;
    FAutoKeyPos: Integer;
    FAutoKeyFrames: Integer;
    { SAM Coupe }
    FIsSAM: Boolean;                        // a SAM Coupe: FSam holds the ASIC's registers
    FSam: TSam;
    FSamVoid: TBank;                        // what a page the machine has no RAM for reads as
    FSaa: TSAA1099;                         // its sound generator
    FSaaAddr: Byte;                         // the register the next data write is for
    FSamSaaOn: Boolean;                     // setting: the SAA1099 is heard
    FSamKB: Integer;                        // setting: the RAM, 256 or 512
    FSamJoyOn: Boolean;                     // setting: the Kempston joystick is connected
    FSamMouseOn: Boolean;                   // setting: the mouse is connected
    FSamClockOn: Boolean;                   // setting: the SAMBUS clock is connected
    FSamPlayFrame: Int64;                   // the frame to press Play at (the tape of an auto load), or -1
    FSamSwapDisk: TDiskImage;               // the disk that goes in drive 1 once SAMDOS has booted
    FSamTrapHits: Integer;                  // files loaded by the SAMDOS trap
    FSamSwapFrame: Int64;                   // the frame to put it in at
    { Commodore 64 }
    FIsC64: Boolean;                        // a C64: FC64 is the machine
    FC64: TC64;
    FC64Shadow: array[0..1] of TDiskImage;  // stand-ins for the .d64 disks in the drives (the media panel asks DiskAt for the name)
    { MSX }
    FIsMSX: Boolean;                        // an MSX: FMsxHw is the machine's hardware
    FMsxHw: TMsxMachine;
    FMsxArmed: Boolean;                     // Play pressed: the tape moves while the program has the motor on
    FMsxClick: Boolean;                     // the click bit of PPI port C
    FMsxDatePending: Boolean;               // an auto load: ENTER answers the disk ROM's date prompt when it comes
    FMsxOwnDisk: Boolean;                   // the disk ROM is QUANTIKA_DISK.ROM (it asks no date)
    FMsxEnterFrom: Int64;                   // the frame ENTER is pressed at, for 4 frames (-1: not now)
    FMsxCompat: Boolean;                    // the MSX1 layout (no expanded slot): from the next reset
    FMsxMapperMode: Integer;                // the memory mapper: 0 auto (off when a tape starts the machine), 1 on, 2 off
    FMsxTapeStart: Boolean;                 // the next reset is an auto load from tape
    { Amstrad CPC }
    FIsCPC: Boolean;                        // a CPC model: FCPC is the machine's hardware
    FCPC: TAmstrad;
    FAYStep: Integer;                       // T-states per AY tick (16; 32 for the CPC's 1 MHz PSG)
    FCPCArmed: Boolean;                     // the user pressed Play: the tape runs while the motor is on
    FCPCOffPending: Boolean;                // the program has switched the motor off, not for long enough to stop the tape yet
    FCPCOffT: Integer;                      // ... since this T-state of the frame
    procedure SetupCPC;
    procedure CPCAutoType(Frames: Integer; const Keys: array of Integer);
    function CPCTypeText(const Text: string; out Error: string): Boolean;
    function CPCDiscProgram: string;
    procedure CPCAutoLoad(FromDisk: Boolean);
    procedure CPCSyncAutoKeys;
    procedure CPCReset(Hard: Boolean);
    procedure CPCPaging;
    procedure CPCPsg(T: Integer; Reg, Value: Byte);
    function CPCTapeIn(T: Integer): Boolean;
    procedure CPCMotor(T: Integer; On_: Boolean);
    procedure CPCMotorSettle(T: Integer);
    procedure CPCTapeOut(T: Integer; Level: Boolean);
    function CPCFdc(Write: Boolean; Reg: Integer; Value: Byte; T: Integer): Byte;
    procedure CPCTapeUpdate(ChipT: Integer);
    function CPCTapeT(ChipT: Integer): Integer; inline;
    function ReadMemCPC(Addr: Word): Byte;
    procedure WriteMemCPC(Addr: Word; Value: Byte);
    function ReadPortCPC(Port: Word; var T: Integer): Byte;
    procedure WritePortCPC(Port: Word; Value: Byte; var T: Integer);
    procedure ExecuteOneCPC;
    function CPCInstrNops(out IoNops: Integer; out IntShort: Boolean): Integer;
    procedure FinishFrameCPC;
    procedure SetupC64;
    procedure C64Reset(Hard: Boolean);
    function RunFrameC64: Boolean;
    procedure StepInstructionC64;
    procedure FinishFrameC64;
    function C64TapeText: string;
    procedure SetupMSX;
    function MSXNow: Int64;
    function MSXTapeT(ChipT: Integer): Integer;
    function MSXTapeIn(T: Integer): Boolean;
    procedure MSXMotor(T: Integer; On_: Boolean);
    procedure MSXTapeUpdate(ChipT: Integer);
    procedure MSXBeeper(T: Integer);
    procedure MSXAutoType(Frames: Integer; const Keys: array of Integer);
    procedure MSXSyncAutoKeys;
    function MSXTypeText(const Text: string; out Error: string): Boolean;
    procedure MSXAutoLoad(FromDisk: Boolean);
    procedure MSXReset(Hard: Boolean);
    procedure MSXPaging;
    procedure MSXPsg(T: Integer; Reg, Value: Byte);
    procedure MSXClick(T: Integer; Level: Boolean);
    function ReadMemMSX(Addr: Word): Byte;
    procedure WriteMemMSX(Addr: Word; Value: Byte);
    function ReadPortMSX(Port: Word; var T: Integer): Byte;
    procedure WritePortMSX(Port: Word; Value: Byte; var T: Integer);
    procedure ExecuteOneMSX;
    procedure FinishFrameMSX;
    procedure SetupSAM;
    procedure SAMStateIO(S: TStream; Save: Boolean);
    function SamSlotCanHold(Slot, What: Integer): Boolean;
    function SetSamSlot(Slot, What: Integer): Boolean;
    procedure SetSamMemory(KB: Integer);
    procedure SAMReset(Hard: Boolean);
    procedure SAMPaging;
    function ReadPortSAM(Port: Word; var T: Integer): Byte;
    procedure WritePortSAM(Port: Word; Value: Byte; var T: Integer);
    procedure SAMRenderUpTo(T: Integer);
    procedure SAMAutoType(Frames: Integer; const Keys: array of Integer);
    procedure SAMSyncAutoKeys;
    function SAMTypeText(const Text: string; out Error: string): Boolean;
    procedure SAMAutoLoad(FromDisk: Boolean);
    procedure SAMCheckTraps;
    procedure CPCCheckTraps;
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
    function IsCPC: Boolean; inline;
    function IsNext: Boolean; inline;
    function RamBanksUsed: Integer;
    procedure NextLoadRoms;
    procedure NextReset(Hard: Boolean);
    procedure NextWriteReg(Reg, Value: Byte);
    function NextReadReg(Reg: Byte): Byte;
    procedure NextPortPaging(Bank: Boolean);
    procedure NextUpdatePaging;
    procedure NextSetDivEntries;
    procedure NextVideoReset;
    procedure NextPaletteWrite(Value: Byte; NineBits: Boolean);
    procedure NextSetPal(Pal, Index: Integer; Value: Word);
    procedure NextClipWrite(Layer: Integer; Value: Byte);
    procedure NextSpriteAttr(Value: Byte);
    procedure NextRenderLine(Line, X0, X1: Integer);
    procedure NextRenderUpTo(T: Integer; Split: Boolean);
    procedure NextDrawTo(T: Integer; Split: Boolean);
    procedure NextCopperRun(T: Integer);
    function NextRasterTime(V, H, FromT: Integer): Integer;
    function NextVideoReg(Reg: Byte): Boolean;
    function NextL2Bank(Addr: Word; Write: Boolean; out Bank: Integer): Boolean;
    procedure NextCopperWrite(Value: Byte);
    procedure DmaQueue(What: Integer);
    procedure DmaWrite(Value: Byte);
    function DmaRead: Byte;
    procedure DmaStart;
    function DmaByte: Boolean;
    procedure DmaRun(Count: Integer);
    procedure NextDacWrite(Port: Word; Value: Byte; T: Integer);
    function NextAltRomIndex: Integer;
    function NextSramBank(Bank: Integer): PBank;
    function NextLineIntActive: Boolean;
    function TurboOn: Boolean; inline;
    function MfPorts(out EnablePort, DisablePort: Byte): Integer;
    function NextMfNmi: Boolean;
    function NextDivNmi: Boolean;
    function NextMfPortRead(Port: Word; out Value: Byte): Boolean;
    procedure NextMfPortWrite(Port: Word);
    function NexFileCall: Boolean;
    procedure NextFlashWrite(Value: Byte);
    function NextFlashRead: Byte;
    procedure NexOnCard;
    procedure SnapIO(S: TStream; Save: Boolean);
    procedure CPCSnapIO(S: TStream; Save: Boolean);
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
    procedure AddAY(Chip: Integer; const Lv: array of Single; Gain: Single; var L, R: Single);
    procedure TapeTrap;
    procedure TapeTrapRest;
    procedure TapeAuto;
    procedure CheckTraps;
    { RST 8 with the DivMMC: remember the game files esxDOS opens }
    procedure NoteEsxdosCall;
    procedure ExecuteOne;
    function U(T: Integer): Integer; inline;
    function LowRead(Addr: Word; T: Integer): Byte; inline;
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
    procedure SetOneBreakpoint(Addr: Word; Flags: Byte);
    procedure SetOnePortBreakpoint(Port: Word; Flags: Byte);
    procedure DeleteBreakRange(R: Integer);
    procedure CheckPortBreak(Port: Word; Write: Boolean);
    function PortBreakMatch(Port: Word; Write: Boolean): Boolean;
    function ProbeBreak: Boolean;
    function GetRecording: Boolean;
    procedure SetRecording(Value: Boolean);
  public
    Keyboard: array[0..7] of Byte;   // half-row state, bit = 0 when pressed
    { The keys of the Next's keyboard that are two Spectrum keys at once
      (EXT_* bits): the combination is pressed, and the Next also reports
      them alone in NR B0-B1 }
    ExtKeys: Word;
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
    MouseReadTick: QWord;      // when a program last read the mouse (GetTickCount64): in use or not
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
    { The NMI button; on the ZX Spectrum Next its M1 button (the Multiface) }
    procedure RequestNMI;
    { The ZX Spectrum Next's DRIVE button: the DivMMC's NMI }
    procedure DriveNMI;
    { Play the tape from now (the tape runs in CPU T-states: see TapeEdge) }
    procedure PlayTape;
    { The Next's firmware started another machine's core (its slot, 8-31):
      ochenta emulates the Next's only, so the Next starts again; -1 if not }
    property ForeignCore: Integer read FForeignCore write FForeignCore;
    { The Next's Multiface is paged in (its NMI menu is running) }
    property MultifaceOn: Boolean read FMfOn;
    { ochenta's own snapshots (.e80: see OchentaSnap.inc), for any model: whether
      it is the only kind this machine can have (the ZX Spectrum Next and
      the ZX-Uno), the machine a file is of (raises if it isn't one), save
      and load (the machine must be that model) }
    function NeedsOwnSnapshot: Boolean;
    class function OwnSnapshotModel(const FileName: string): TSpectrumModel;
    procedure SaveOwnSnapshot(const FileName: string);
    procedure LoadOwnSnapshot(const FileName: string);
    procedure Retn; override;
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
    { Type one symbol of the virtual keyboard (a UTF-8 character) the way the machine's keys give it
      ("~" and "\" too, as characters). False if the machine has no way to type it; DryRun only tells
      whether it has. }
    function TypeSymbol(const Sym: string; DryRun: Boolean = False): Boolean;
    { Full path of ROM Index for the current model }
    function RomPath(Index: Integer): string;
    { Reset and load from tape the way a user would (LOAD "" or Loader menu). }
    procedure AutoLoad(FromDisk: Boolean = False; C64Drive: Integer = 0);
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
    { Make First..Last one breakpoint (removing the breakpoints there were in
      it), before setting its condition and flags on First }
    procedure SetBreakRange(First, Last: Word; Port: Boolean);
    { The range Addr is in, -1 if none }
    function BreakRangeIndex(Addr: Word; Port: Boolean): Integer;
    { The last address of the breakpoint at Addr (Addr itself if it is not
      a range) }
    function BreakRangeLast(Addr: Word; Port: Boolean): Word;
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
    { The RAM at Addr, also under a CPC's ROMs (what the Adventure Debugger reads and
      writes: the game's database and flags); Peek and Poke on the others }
    function PeekRam(Addr: Word): Byte;
    procedure PokeRam(Addr: Word; Value: Byte);
    function FetchMem(Addr: Word; T: Integer): Byte; override;
    property Breakpoint[Addr: Word]: Byte read GetBreakpoint write SetBreakpoint;
    property PortBreakpoint[Port: Word]: Byte read GetPortBreakpoint write SetPortBreakpoint;
    property TempBreak: Integer read FTempBreak write FTempBreak;
    { Adventure Debugger: Map has DAAD_* flags for every address (the condacts of
      the game's processes); while on, the interpreter's condact fetches are
      followed. Off with nil. }
    procedure SetDaadMap(Map: PByte);
    property DaadOn: Boolean read FDaadOn;
    { Where the flags are while a condact runs (IX on the Z80 machines, a fixed address on the C64), and the stack pointer }
    function DaadFlagsBase: Word;
    function DaadStackPointer: Word;
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
    function PagingState: TPagingState;
    { Debugger: the machine now, and back to a saved state (False if the
      model has changed since) }
    function SaveState: TMachineState;
    function LoadState(S: TMachineState): Boolean;
    { Debugger: page RAM bank 0-7 in at C000 (128K/+2/+3 normal paging).
      Ignores the paging lock. False if this machine can't. }
    function SetSlot3Bank(Bank: Integer): Boolean;
    { Debugger, CPC: what a slot can hold (as SlotBank) and putting it there }
    function CPCSlotCanHold(Slot, What: Integer): Boolean;
    function SetCPCSlot(Slot, What: Integer): Boolean;
    { What is at Addr now: RAM, ROM (also the DivMMC's EEPROM or its
      write-protected bank when paged in) or nothing }
    function MemoryAt(Addr: Word): TMemoryAt;
    { Debugger: write a byte where the CPU would; ROM only if RomWritable }
    procedure Poke(Addr: Word; Value: Byte);
    property TrackPrevRegs: Boolean read FTrackPrev write SetTrackPrev;
    property PrevRegs: TZ80Regs read FPrevRegs write FPrevRegs;
    property PrevPaging: TPagingState read FPrevPaging write FPrevPaging;
  public
    { Name (no folder) of the last game file loaded: a tape, disk or
      snapshot opened in ochenta, or a .TAP/.TZX/.Z80/.SNA/.DSK that esxDOS opened
      from the SD card. A short string: the emulation thread writes it. }
    LastMediaFile: ShortString;
    property StepCount: LongWord read FStepCount;
    { Amstrad CPC .SNA snapshots (the model they say, 64K or 128K) }
    procedure LoadCPCSna(const FileName: string);
    procedure SaveCPCSna(const FileName: string);
    procedure RenderUpTo(T: Integer);
    { Draw the frame again from its first line (tests) }
    procedure RestartRender;
    { Render the picture up to the current CPU position (after a break) }
    procedure RenderToCurrent;
    { CPU clock multiplier: 1, 2, 4 ... 32. Interrupts stay at 50 Hz; the
      change applies from the next frame. }
    procedure SetSpeed(Value: Integer);
    property Speed: Integer read FSpeed;
    { Fast loading, and a tape playing in real time (what the ROM trap left
      to the program's own loader): the emulator runs flat out meanwhile }
    function TapeAccelerating: Boolean;
    { A SAM Coupe disk being read or written with fast disk access on: as fast as possible, as a tape is }
    function DiskAccelerating: Boolean;
    { Stop, as the user does it: it keeps Auto play from starting the tape
      again for the same load (PlayTape is the user's Play) }
    procedure StopTape;
    { Stopped by the user or by a TZX block, with a load asking for it:
      Auto play waits for the next one }
    property TapeAutoHeld: Boolean read FTapeHeld;
    { What the tape is doing, in words: playing, end of tape, stopped
      (and held, for Auto play) }
    function TapeStateText: string;
    { Disk transfers without real drive timing }
    procedure SetFastDisk(Value: Boolean);
    function GetFastDisk: Boolean;
    function GetDriveB: Boolean;
    procedure SetDriveB(Value: Boolean);
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
    procedure WriteNextReg(Reg, Value: Byte; T: Integer); override;
    { Copy of the current frame in $FFRRGGBB pixels, SCREEN_WIDTH x SCREEN_HEIGHT. }
    procedure CopyFrameBuffer(Dest: PLongWord);
    function Samples: Pointer;
    property SampleCount: Integer read FSampleCount;
    property Model: TSpectrumModel read FModel;
    property Info: TModelInfo read FInfo;
    { The Amstrad CPC's hardware (nil on the Spectrum models) }
    property CPC: TAmstrad read FCPC;
    { The SAM Coupe's ASIC (nil on the other models) }
    property SAM: TSam read FSam;
    { The Commodore 64's hardware (nil on the other models) }
    property C64Hw: TC64 read FC64;
    { The MSX's hardware (nil on the other models) }
    property MSXHw: TMsxMachine read FMsxHw;
    { The MSX2's memory mapper (MSX_MAPPER_*): from the next reset }
    property MsxMapperMode: Integer read FMsxMapperMode write FMsxMapperMode;
    { The MSX2 with the slots of an MSX1: none expanded, no disk interface (MSX1 programs that use FFFFh as RAM or look for
      RAM in a primary slot alone need it); from the next reset }
    property MsxCompat: Boolean read FMsxCompat write FMsxCompat;
    { Whether the SAM Coupe's SAA1099 is heard (it is always emulated) }
    property SamSaaOn: Boolean read FSamSaaOn write FSamSaaOn;
    { The SAM Coupe's registers, for the debugger: Reg is the port ($F9 the line interrupt,
      $FA LMPR, $FB HMPR, $FC VMPR, $FE the border), $1F9 the status (the interrupts),
      $100 + N the CLUT's entry N, $200 + N the SAA1099's register N. Writing one is as
      an OUT would (paging included). }
    function SamRegister(Reg: Integer): Byte;
    procedure SetSamRegister(Reg: Integer; Value: Byte);
    { The debugger's chips window on the 16K to +3 and the Amstrad CPC (SpectrumChips.inc): the ports and the chips'
      registers by a code of their own (see there), whether the machine has it, its value, and writing it as an OUT
      would (not in the port log, and no port breakpoint stops it) }
    function ChipRegisterExists(Code: Integer): Boolean;
    function ChipRegister(Code: Integer): Byte;
    procedure SetChipRegister(Code: Integer; Value: Byte);
    procedure DebugOut(Port: Word; Value: Byte);
    { A SAM Coupe's machine state into S (Save) or from it: the RAM, the CPU, the ASIC and
      the sound generator (the body of an ochenta snapshot) }
    procedure SAMSnapIO(S: TStream; Save: Boolean);
    { The SAM Coupe's RAM in K (256 or 512): changing it on a SAM resets it }
    property SamMemoryKB: Integer read FSamKB write SetSamMemory;
    { Whether the SAM Coupe has a Kempston joystick (port 31, as KempstonState) }
    property SamJoystickOn: Boolean read FSamJoyOn write FSamJoyOn;
    property SamMouseOn: Boolean read FSamMouseOn write FSamMouseOn;
    property SamClockOn: Boolean read FSamClockOn write FSamClockOn;
    { A SAMDOS disk boots, then the disk wanted goes in drive 1 }
    procedure SamDosThen(Dos, Disk: TDiskImage);
    property SamTrapHits: Integer read FSamTrapHits;
    property Cpu: TZ80 read FCpu;
    property AY: TAY8912 read FAY;
    property Tape: TTape read FTape;
    { Amstrad CPC: Play has been pressed (the tape runs while the motor is on) }
    property CPCTapeArmed: Boolean read FCPCArmed;
    property FDC: TUPD765 read FFDC;
    { The disks, whichever controller the machine has: the SAM Coupe's WD1772
      or the uPD765 of the +3 and the CPC }
    function DiskAt(Drive: Integer): TDiskImage;
    procedure InsertDiskAt(Drive: Integer; Disk: TDiskImage);
    function EjectDiskAt(Drive: Integer): TDiskImage;
    function DiskLastAccess(Drive: Integer): QWord;
    property DriveBOn: Boolean read GetDriveB write SetDriveB;
    { MSX: keys held down for that many frames (after the keys queued before): for the test tools }
    procedure MSXHoldKeys(Frames: Integer; const Keys: array of Integer);
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
    { The Currah µSpeech (connected while CurrahOn; its ROMs loaded first) }
    property Currah: TCurrah read FCurrah;
    property CurrahOn: Boolean read FCurrahOn write FCurrahOn;
    { ZX Spectrum Next: the folder of its distribution (ROMs in
      machines/next), set before choosing the model }
    property NextDir: string read FNextDir write FNextDir;
    { Next register, as port 253B reads it, and writing one (debugger) }
    function NextRegister(Reg: Byte): Byte;
    procedure SetNextRegister(Reg, Value: Byte);
    { Its MMU: the 8K page in each slot (255 = ROM) }
    function NextMMU(Slot: Integer): Byte;
    { Load a .nex program (as NextZXOS's .nexload does) and start it; raises
      on errors }
    procedure LoadNex(const FileName: string);
    { Boot through its firmware (TBBLUE.FW on the card, started by the FPGA's
      boot ROM in NextBootRom) instead of starting NextZXOS directly; set
      before choosing the model }
    property NextFirmwareBoot: Boolean read FNextFirmware write FNextFirmware;
    property NextBootRom: string read FNextBootRomFile write FNextBootRomFile;
    { What NR 00 says the machine is: $08, an emulator (with $0A, a ZX
      Spectrum Next, the firmware shows the Sinclair logo; with $08 the
      TBBlue one) }
    property NextMachineId: Byte read FNextMachineId write FNextMachineId;
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

  { ExtKeys bits: NR B0 (bits 0-7) and NR B1 (bits 8-15) }
  EXT_RIGHT = 0; EXT_LEFT = 1; EXT_DOWN = 2; EXT_UP = 3; EXT_PERIOD = 4; EXT_COMMA = 5;
  EXT_QUOTE = 6; EXT_SEMICOLON = 7; EXT_EXTEND = 8; EXT_CAPSLOCK = 9; EXT_GRAPH = 10;
  EXT_TRUEVIDEO = 11; EXT_INVVIDEO = 12; EXT_BREAK = 13; EXT_EDIT = 14; EXT_DELETE = 15;
  { The Spectrum keys each one is }
  EXT_KEYS: array[0..15, 0..1] of Integer = (
    (KEY_CAPS, KEY_8), (KEY_CAPS, KEY_5), (KEY_CAPS, KEY_6), (KEY_CAPS, KEY_7),
    (KEY_SYM, KEY_M), (KEY_SYM, KEY_N), (KEY_SYM, KEY_P), (KEY_SYM, KEY_O),
    (KEY_CAPS, KEY_SYM), (KEY_CAPS, KEY_2), (KEY_CAPS, KEY_9), (KEY_CAPS, KEY_3),
    (KEY_CAPS, KEY_4), (KEY_CAPS, KEY_SPACE), (KEY_CAPS, KEY_1), (KEY_CAPS, KEY_0));

  NO_MEMORY = -100;   // slot with nothing paged in (16K model)

  MSX_MAPPER_AUTO = 0;    // MsxMapperMode: the mapper is there, except when a tape starts the machine
  MSX_MAPPER_ON = 1;
  MSX_MAPPER_OFF = 2;

  BP_EXEC = 1;
  BP_READ = 2;
  BP_WRITE = 4;
  BP_DISABLED = $80;   // kept with its type and condition, but never stops

  Palette: array[0..15] of LongWord = (
    $FF000000, $FF0000D8, $FFD80000, $FFD800D8, $FF00D800, $FF00D8D8, $FFD8D800, $FFD8D8D8,
    $FF000000, $FF0000FF, $FFFF0000, $FFFF00FF, $FF00FF00, $FF00FFFF, $FFFFFF00, $FFFFFFFF);

implementation

uses
  ZStream, FatFS, Plus3FS, Lang;

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
  FAY3 := TAY8912.Create;
  FTape := TTape.Create;
  FTape.OnEdge := @TapeEdge;
  FFDC := TUPD765.Create;
  FWD := TWD1772.Create;
  FSaa := TSAA1099.Create;
  FSamSaaOn := True;
  FSamKB := 512;
  FSamJoyOn := True;
  FSamMouseOn := False;
  FSamClockOn := True;
  FProbeBus := TProbeBus.Create;
  TProbeBus(FProbeBus).Peek := @Peek;
  FProbeCpu := TZ80.Create(FProbeBus);
  FRecorder := TTapeRecorder.Create(FTape);
  FDiv := TDivMMC.Create;
  FCurrah := TCurrah.Create;
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
  FUserSpeed := 1;
  FNextSpeed := 1;
  FNextDir := ExtractFilePath(ExcludeTrailingPathDelimiter(ARomDir)) + 'specnext';
  FNextMachineId := $08;
  FNextFirmware := True;
  FNextBootRomFile := IncludeTrailingPathDelimiter(ARomDir) + 'tbblue_loader.rom';
  FTempBreak := -1;
  FUnoAutoLoad := -1;
  FForeignCore := -1;
  FDaadFetch := -1;
  FastLoad := True;
  AutoPlayTape := True;
  FVolume := 0.7;
  FContentionOn := True;
  FSnowOn := True;
  FloppyNoise := True;
  FFloppySound := TFloppySound.Create(fkSpectrum);
  ConditionPeek := @Peek;    // @x in breakpoint conditions
  SetModel(AModel);
end;

destructor TSpectrum.Destroy;
begin
  ClearBreakpoints;
  FRecorder.Free;
  FFloppySound.Free;
  FDiv.Free;
  FCurrah.Free;
  FProbeCpu.Free;
  FProbeBus.Free;
  FC64Shadow[0].Free;
  FC64Shadow[1].Free;
  FC64.Free;
  FMsxHw.Free;
  FSam.Free;
  FSaa.Free;
  FCPC.Free;
  FFDC.Free;
  FWD.Free;
  FTape.Free;
  FAY3.Free;
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
  if FInfo.Memory in [mkCPC, mkSAM, mkMSX, mkC64] then Exit;   // SetupCPC, SetupSAM, SetupMSX, SetupC64
  if FInfo.Memory = mkZXUno then
  begin
    LoadZXUnoFlash;
    Exit;
  end;
  if FInfo.Memory = mkZXNext then
  begin
    NextLoadRoms;
    Exit;
  end;
  for I := 0 to FInfo.RomCount - 1 do
  begin
    FileName := RomPath(I);
    if not FileExists(FileName) then
      raise Exception.CreateFmt(_('ROM file not found: %s'), [FileName]);
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
  if (Result = '') and (FInfo.RomFiles[Index and 3] = '') then
    Result := ''                          // a ROM the model has no standard file for (the MSX's disk interface)
  else if Result = '' then
    Result := IncludeTrailingPathDelimiter(FRomDir) + FInfo.RomFiles[Index and 3]
  else if not ((Result[1] in ['/', '\']) or ((Length(Result) > 1) and (Result[2] = ':'))) then
    Result := IncludeTrailingPathDelimiter(FRomDir) + Result;
end;

procedure TSpectrum.SetModel(AModel: TSpectrumModel);
var
  WasUno, WasNext, WasCPC, WasSAM, WasMSX, WasC64: Boolean;
  OldModel: TSpectrumModel;
begin
  OldModel := FModel;
  WasCPC := FIsCPC;
  WasSAM := FIsSAM;
  WasMSX := FIsMSX;
  WasC64 := FIsC64;
  WasUno := IsZXUno;
  WasNext := IsNext;
  FModel := AModel;
  FInfo := ModelInfo[AModel];
  FIsCPC := FInfo.Memory = mkCPC;
  FIsSAM := FInfo.Memory = mkSAM;
  FIsMSX := FInfo.Memory = mkMSX;
  FIsC64 := FInfo.Memory = mkC64;
  if FIsCPC then FAYStep := 32 else FAYStep := 16;
  FRecorder.Raw := FIsCPC or FIsSAM or FIsMSX;
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
  // The Next has its DivMMC built in, its ROM and RAM in the SRAM, and the
  // Z80N's extra instructions
  if IsNext then
  begin
    FDiv.UseMemory(@FNextSram[4], @FNextSram[8]);
    FDivOn := True;
  end
  else if WasNext then FDivOn := False;
  FCpu.Z80N := IsNext;
  Z80NMnemonics := IsNext;
  FDiv.ControlReadable := IsNext;
  if not IsNext then FDiv.NextEntries := False;
  BuildContention;
  FTape.ClockHz := FInfo.ClockHz;
  // TZX's "stop the tape if in 48K mode"
  FTape.StopIf48K := FModel in [sm16K, sm48K];
  // A TZX's pulses are in 3.5 MHz T-states: the SAM's 6 MHz stretches them
  if FIsSAM then FTape.SetPulseScale(12, 7) else FTape.SetPulseScale(1, 1);
  FTape.FinalEdge := FIsSAM or FIsCPC;
  if FIsCPC then FTape.ShortPauseExtraMs := 0.5 else FTape.ShortPauseExtraMs := 0;
  FFDC.ClockHz := FInfo.ClockHz;
  if FIsSAM or FIsMSX then FWD.ClockHz := FInfo.ClockHz;
  UpdateContend;
  if FIsSAM then
  begin
    try
      SetupSAM;
    except
      // No ROM: stay as we were
      FModel := OldModel;
      FInfo := ModelInfo[OldModel];
      FIsCPC := WasCPC;
      FIsSAM := WasSAM;
      FIsMSX := WasMSX;
      FIsC64 := WasC64;
      if FIsCPC then FAYStep := 32 else FAYStep := 16;
      FRecorder.Raw := FIsCPC or FIsSAM or FIsMSX;
      BuildContention;
      FTape.ClockHz := FInfo.ClockHz;
      if WasSAM then FTape.SetPulseScale(12, 7) else FTape.SetPulseScale(1, 1);
      FTape.FinalEdge := WasSAM or WasCPC;
      if WasCPC then FTape.ShortPauseExtraMs := 0.5 else FTape.ShortPauseExtraMs := 0;
      FFDC.ClockHz := FInfo.ClockHz;
      if WasSAM or WasMSX then FWD.ClockHz := FInfo.ClockHz;
      if WasCPC then FTape.ClockHz := 3500000;
      raise;
    end;
  end;
  if FIsCPC then
  begin
    try
      SetupCPC;
    except
      // No firmware: stay as we were
      FModel := OldModel;
      FInfo := ModelInfo[OldModel];
      FIsCPC := WasCPC;
      FIsSAM := WasSAM;
      FIsMSX := WasMSX;
      FIsC64 := WasC64;
      if FIsCPC then FAYStep := 32 else FAYStep := 16;
      FRecorder.Raw := FIsCPC or FIsSAM or FIsMSX;
      if not WasCPC then FreeAndNil(FCPC);
      BuildContention;
      FTape.ClockHz := FInfo.ClockHz;
      if WasSAM then FTape.SetPulseScale(12, 7) else FTape.SetPulseScale(1, 1);
      FTape.FinalEdge := WasSAM or WasCPC;
      if WasCPC then FTape.ShortPauseExtraMs := 0.5 else FTape.ShortPauseExtraMs := 0;
      FFDC.ClockHz := FInfo.ClockHz;
      if WasSAM or WasMSX then FWD.ClockHz := FInfo.ClockHz;
      if WasCPC then FTape.ClockHz := 3500000;
      raise;
    end;
  end;
  if FIsMSX then
  begin
    try
      SetupMSX;
    except
      // No BIOS: stay as we were
      FModel := OldModel;
      FInfo := ModelInfo[OldModel];
      FIsCPC := WasCPC;
      FIsSAM := WasSAM;
      FIsMSX := WasMSX;
      FIsC64 := WasC64;
      if FIsCPC then FAYStep := 32 else FAYStep := 16;
      FRecorder.Raw := FIsCPC or FIsSAM or FIsMSX;
      if not WasMSX then FreeAndNil(FMsxHw);
      BuildContention;
      FTape.ClockHz := FInfo.ClockHz;
      if WasSAM then FTape.SetPulseScale(12, 7) else FTape.SetPulseScale(1, 1);
      FTape.FinalEdge := WasSAM or WasCPC;
      if WasCPC then FTape.ShortPauseExtraMs := 0.5 else FTape.ShortPauseExtraMs := 0;
      FFDC.ClockHz := FInfo.ClockHz;
      if WasSAM or WasMSX then FWD.ClockHz := FInfo.ClockHz;
      if WasCPC then FTape.ClockHz := 3500000;
      raise;
    end;
  end;
  if FIsC64 then
  begin
    try
      SetupC64;
    except
      // No ROMs: stay as we were
      FModel := OldModel;
      FInfo := ModelInfo[OldModel];
      FIsCPC := WasCPC;
      FIsSAM := WasSAM;
      FIsMSX := WasMSX;
      FIsC64 := WasC64;
      if FIsCPC then FAYStep := 32 else FAYStep := 16;
      FRecorder.Raw := FIsCPC or FIsSAM or FIsMSX;
      if not WasC64 then FreeAndNil(FC64);
      BuildContention;
      FTape.ClockHz := FInfo.ClockHz;
      if WasSAM then FTape.SetPulseScale(12, 7) else FTape.SetPulseScale(1, 1);
      FTape.FinalEdge := WasSAM or WasCPC;
      if WasCPC then FTape.ShortPauseExtraMs := 0.5 else FTape.ShortPauseExtraMs := 0;
      FFDC.ClockHz := FInfo.ClockHz;
      if WasSAM or WasMSX then FWD.ClockHz := FInfo.ClockHz;
      if WasCPC then FTape.ClockHz := 3500000;
      raise;
    end;
  end;
  // The hardware of the machine left is only freed once the new one is ready: a machine that can't
  // start (an MSX2 without its ROMs) leaves the old one as it was
  if not FIsSAM then FreeAndNil(FSam);
  if not FIsCPC then FreeAndNil(FCPC);
  if not FIsMSX then FreeAndNil(FMsxHw);
  if not FIsC64 then FreeAndNil(FC64);
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
  if FIsCPC then
  begin
    CPCReset(Hard);
    Exit;
  end;
  if FIsSAM then
  begin
    SAMReset(Hard);
    Exit;
  end;
  if FIsMSX then
  begin
    MSXReset(Hard);
    Exit;
  end;
  if FIsC64 then
  begin
    C64Reset(Hard);
    Exit;
  end;
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
  // A machine's own turbo goes with a reset (the Next and the ZX-Uno set
  // theirs again); the speed setting stays
  FNextSpeed := 1;
  SetSpeed(FUserSpeed);
  if IsZXUno then
  begin
    ZXUnoBoot(Hard);
    // Its turbo register survives a soft reset (a hard one clears it)
    FNextSpeed := 1 shl ((FZXReg[$0B] shr 6) and 3);
    SetSpeed(FUserSpeed);
  end;
  if IsNext then NextReset(Hard);
  FCpu.Reset(Hard);
  FCpu.T := 0;
  FAY.Reset;
  FAY2.Reset;
  FAY3.Reset;
  FillChar(FAYPan, SizeOf(FAYPan), 3);
  FDiv.Reset(Hard);
  FCurrah.Reset;
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
  FNextDrawnX := 0;
  FRenderCell := 0;
  FEventCount := 0;
  FBeeperLevel := 0;
  FSamplePos := 0;
  FAYTickT := 0;
  UpdatePaging;
end;

procedure TSpectrum.RequestNMI;
begin
  if FIsC64 then
  begin
    FC64.Cpu.NMIEdge := True;      // (the RESTORE key does it too)
    Exit;
  end;
  if FIsCPC or FIsMSX then Exit;   // the CPC and the MSX have no NMI button
  // The Next's buttons work as NR 06 lets them (NextZXOS sets it)
  if IsNext then
  begin
    if (FNextReg[$06] and 8) <> 0 then NextMfNmi;
  end
  else
    FNMIRequest := True;
end;

procedure TSpectrum.PlayTape;
begin
  // The user's Play: Auto play is free to act again, and the load under way,
  // if any, is the one to stop the tape at the end of
  if FIsCPC then
  begin
    // Play pressed: the tape moves while the program has the motor on
    FCPCArmed := True;
    CPCTapeUpdate(FCPC.ChipT);
    Exit;
  end;
  if FIsMSX then
  begin
    FMsxArmed := True;
    MSXTapeUpdate(U(FCpu.T));
    Exit;
  end;
  if FIsC64 then
  begin
    FC64.PlayTape;
    Exit;
  end;
  FTapeHeld := False;
  FLoadedSincePlay := FLoadDemand;
  // With fast loading, a moment of silence first: the ROM's loader, if it
  // is waiting, goes back to LD-START (056C) and takes the block at once
  if FastLoad then FTape.Play(FCpu.T + FInfo.ClockHz div 10 * FSpeed)
  else FTape.Play(FCpu.T);
end;

function TSpectrum.TapeStateText: string;
begin
  if FIsC64 then Exit(C64TapeText);
  if (FIsMSX and FMsxArmed and not FMsxHw.Motor and not FTape.Playing) or
     (FIsCPC and FCPCArmed and not FCPC.Motor and not FTape.Playing) then
    Result := _('play pressed, waiting for the motor')
  else if FTape.Playing then Result := 'playing'
  else if (FTape.Count > 0) and (FTape.Current >= FTape.Count) then Result := _('end of tape')
  else if FTapeHeld and AutoPlayTape then Result := _('stopped (auto play waits for the next load)')
  else Result := 'stopped';
end;

procedure TSpectrum.StopTape;
begin
  if FIsCPC then
  begin
    FCPCArmed := False;
    CPCTapeUpdate(FCPC.ChipT);
    Exit;
  end;
  if FIsMSX then
  begin
    FMsxArmed := False;
    MSXTapeUpdate(U(FCpu.T));
    Exit;
  end;
  if FIsC64 then
  begin
    FC64.StopTape;
    Exit;
  end;
  FTape.Stop;
  // Stopped with a load asking for the tape: not again for that one
  if FLoadDemand then FTapeHeld := True;
end;

{ Auto play/stop, once a frame. The Spectrum asks for the tape when it reads
  the EAR bit over and over: a loader does it every few T-states (hundreds of
  times a frame), a keyboard scan a few times. So a load starts after
  DEMAND_FRAMES frames of that, and ends after QUIET_FRAMES without it (the
  ROM's LD-BYTES says so sooner: see CheckTrap). The tape plays when a load
  starts (or goes on being asked for) and stops when it ends, where it is;
  stopped by the user or by a TZX block, it waits for the next load. }
procedure TSpectrum.TapeAuto;
const
  DEMAND_READS = 300;     // EAR reads in a frame (at 1x) that make a loader
  DEMAND_FRAMES = 10;     // a fifth of a second of them starts a load
  QUIET_FRAMES = 75;      // one and a half seconds without them end it
begin
  if FTape.Epoch <> FTapeEpoch then
  begin
    // Rewound, another block chosen, a tape in or out: a fresh start
    FTapeEpoch := FTape.Epoch;
    FTapeHeld := False;
  end;
  // A TZX block stopped it: not started again for what asked for it
  if FTape.StoppedByBlock then
  begin
    if not FBlockStopSeen then FTapeHeld := True;
    FBlockStopSeen := True;
  end
  else FBlockStopSeen := False;
  if FTapeReads div FSpeed >= DEMAND_READS then
  begin
    Inc(FDemandFrames);
    FQuietFrames := 0;
  end
  else
  begin
    FDemandFrames := 0;
    Inc(FQuietFrames);
  end;
  FTapeReads := 0;
  // The ROM's LD-BYTES returned in this frame (after reading as hard as ever,
  // so the count above doesn't say it): the load ends soon, if no other follows
  if FLoadEnded then
  begin
    FLoadEnded := False;
    FDemandFrames := 0;
    FQuietFrames := Max(FQuietFrames, QUIET_FRAMES - 20);
  end;
  if not AutoPlayTape then
  begin
    FLoadDemand := False;
    Exit;
  end;
  if not FLoadDemand then
  begin
    if FDemandFrames >= DEMAND_FRAMES then
    begin
      // A new load: Auto play is free again
      FLoadDemand := True;
      FTapeHeld := False;
      FLoadedSincePlay := FTape.Playing;
    end;
  end
  else if FQuietFrames >= QUIET_FRAMES then
  begin
    FLoadDemand := False;
    // Done loading: stopped where it is
    if FTape.Playing and FLoadedSincePlay then FTape.Stop;
    FLoadedSincePlay := False;
  end;
  if FLoadDemand and not FTape.Playing and not FTapeHeld and FTape.HasMore then
  begin
    FLoadedSincePlay := True;
    FTape.Play(FCpu.T);
  end;
end;

procedure TSpectrum.DriveNMI;
begin
  if IsNext and ((FNextReg[$06] and $10) <> 0) then NextDivNmi;
end;

function TSpectrum.RamBank(Index: Integer): PBank;
begin
  if FIsCPC then Exit(PBank(FCPC.RamBank(Index)));
  if IsNext or FIsSAM then Result := @FRam[Index mod RAM_BANKS] else Result := @FRam[Index and 7];
end;

procedure TSpectrum.UpdatePaging;
const
  SpecialMaps: array[0..3, 0..3] of Integer = (
    (0, 1, 2, 3), (4, 5, 6, 7), (4, 5, 6, 3), (4, 7, 6, 3));
var
  Slot, Bank, Rom: Integer;
begin
  if FIsCPC then
  begin
    CPCPaging;
    Exit;
  end;
  if FIsMSX then
  begin
    MSXPaging;
    Exit;
  end;
  if FIsSAM then
  begin
    SAMPaging;
    Exit;
  end;
  if IsNext then
  begin
    NextUpdatePaging;
    Exit;
  end;
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
  // The 8K pages the CPU reads and writes
  for Slot := 0 to 7 do
  begin
    FPage[Slot] := @FSlot[Slot shr 1]^[(Slot and 1) * $2000];
    Bank := FSlotBank[Slot shr 1];
    FPageRO[Slot] := Bank < 0;
    FPageScreen[Slot] := (Bank = FScreenBank) and not Odd(Slot);
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

destructor TMachineState.Destroy;
begin
  Cpu.Free;
  inherited Destroy;
end;

function TSpectrum.SaveState: TMachineState;
var
  MS: TMemoryStream;
begin
  Result := TMachineState.Create;
  Result.Model := FModel;
  Result.Cpu := TZ80.Create(FProbeBus);
  Result.Cpu.CopyStateFrom(FCpu);
  if FIsCPC then
  begin
    MS := TMemoryStream.Create;
    try
      FCPC.SaveState(MS);
      SetLength(Result.CPCState, MS.Size);
      Move(MS.Memory^, Result.CPCState[0], MS.Size);
    finally
      MS.Free;
    end;
  end;
  if FIsSAM then
  begin
    MS := TMemoryStream.Create;
    try
      SAMStateIO(MS, True);
      SetLength(Result.SamState, MS.Size);
      Move(MS.Memory^, Result.SamState[0], MS.Size);
    finally
      MS.Free;
    end;
  end;
  if FIsC64 then
  begin
    MS := TMemoryStream.Create;
    try
      FC64.StateIO(MS, True);
      SetLength(Result.C64State, MS.Size);
      Move(MS.Memory^, Result.C64State[0], MS.Size);
    finally
      MS.Free;
    end;
  end;
  SetLength(Result.Ram, RamBanksUsed);
  Move(FRam, Result.Ram[0], RamBanksUsed * SizeOf(TBank));
  Move(FNextReg, Result.NextReg, SizeOf(FNextReg));
  Move(FNextMMU, Result.NextMMU, SizeOf(FNextMMU));
  if IsNext then
  begin
    SetLength(Result.NextSram, Length(FNextSram));
    Move(FNextSram, Result.NextSram[0], SizeOf(FNextSram));
  end;
  Result.NextBootOn := FNextBootOn;
  Result.MfNmi := FMfNmi;
  Result.MfOn := FMfOn;
  Result.MfInvisible := FMfInvisible;
  Result.NmiStackless := FNmiStackless;
  Result.CopperPC := FCopperPC;
  Result.CopperClk := FCopperClk;
  Result.CopperDue := FCopperDue;
  Result.CopperStopped := FCopperStopped;
  Result.CopperRestarted := FCopperRestarted;
  Result.DivNmiButton := FDiv.NmiButton;
  Result.NextSel := FNextSel;
  Result.PortDFFD := FPortDFFD;
  FDiv.SaveState(Result.DivState);
  Result.CurrahPaged := FCurrah.Paged;
  Result.Port7FFD := FPort7FFD;
  Result.Port1FFD := FPort1FFD;
  Result.Border := FBorder;
  Result.UlaOut := FUlaOut;
  Result.TimexPort := FTimexPort;
  Result.ULAPlusReg := FULAPlusReg;
  Result.ULAPlusMode := FULAPlusMode;
  Result.ZXUnoReg := FZXUnoReg;
  Move(FULAPlusPal, Result.ULAPlusPal, SizeOf(FULAPlusPal));
  Move(FZXReg, Result.ZXReg, SizeOf(FZXReg));
  Result.ScreenBank := FScreenBank;
  Result.FrameCount := FFrameCount;
  Result.CpuTBase := FCpuTBase;
  Result.RenderLine := FRenderLine;
  Result.RenderCell := FRenderCell;
  Result.EventCount := FEventCount;
  Result.AYTickT := FAYTickT;
  Result.SamplePos := FSamplePos;
  Result.PrevRegs := FPrevRegs;
  Result.PrevPaging := FPrevPaging;
  Result.StepCount := FStepCount;
  Move(FPortLog, Result.PortLog, SizeOf(FPortLog));
  Result.PortLogPos := FPortLogPos;
  Result.PortLogCount := FPortLogCount;
end;

function TSpectrum.LoadState(S: TMachineState): Boolean;
var
  I: Integer;
  MS: TMemoryStream;
begin
  Result := S.Model = FModel;
  if not Result then Exit;
  FCpu.CopyStateFrom(S.Cpu);
  if FIsCPC and (Length(S.CPCState) > 0) then
  begin
    MS := TMemoryStream.Create;
    try
      MS.WriteBuffer(S.CPCState[0], Length(S.CPCState));
      MS.Position := 0;
      FCPC.LoadState(MS);
    finally
      MS.Free;
    end;
    CPCPaging;
  end;
  if FIsSAM and (Length(S.SamState) > 0) then
  begin
    MS := TMemoryStream.Create;
    try
      MS.WriteBuffer(S.SamState[0], Length(S.SamState));
      MS.Position := 0;
      SAMStateIO(MS, False);
    finally
      MS.Free;
    end;
  end;
  if FIsC64 and (Length(S.C64State) > 0) then
  begin
    MS := TMemoryStream.Create;
    try
      MS.WriteBuffer(S.C64State[0], Length(S.C64State));
      MS.Position := 0;
      FC64.StateIO(MS, False);
    finally
      MS.Free;
    end;
  end;
  Move(S.Ram[0], FRam, Length(S.Ram) * SizeOf(TBank));
  Move(S.NextReg, FNextReg, SizeOf(FNextReg));
  Move(S.NextMMU, FNextMMU, SizeOf(FNextMMU));
  if Length(S.NextSram) = Length(FNextSram) then Move(S.NextSram[0], FNextSram, SizeOf(FNextSram));
  FNextBootOn := S.NextBootOn;
  FMfNmi := S.MfNmi;
  FMfOn := S.MfOn;
  FMfInvisible := S.MfInvisible;
  FNmiStackless := S.NmiStackless;
  FCopperPC := S.CopperPC;
  FCopperClk := S.CopperClk;
  FCopperDue := S.CopperDue;
  FCopperStopped := S.CopperStopped;
  FCopperRestarted := S.CopperRestarted;
  FNextSel := S.NextSel;
  FPortDFFD := S.PortDFFD;
  FDiv.LoadState(S.DivState);
  FDiv.NmiButton := S.DivNmiButton;
  FCurrah.Paged := S.CurrahPaged;
  FPort7FFD := S.Port7FFD;
  FPort1FFD := S.Port1FFD;
  FBorder := S.Border;
  FUlaOut := S.UlaOut;
  FTimexPort := S.TimexPort;
  FULAPlusReg := S.ULAPlusReg;
  FULAPlusMode := S.ULAPlusMode;
  FZXUnoReg := S.ZXUnoReg;
  for I := 0 to 63 do SetULAPlusEntry(I, S.ULAPlusPal[I]);
  Move(S.ZXReg, FZXReg, SizeOf(FZXReg));
  FScreenBank := S.ScreenBank;
  FFrameCount := S.FrameCount;
  FCpuTBase := S.CpuTBase;
  FRenderLine := S.RenderLine;
  FNextDrawnX := 0;
  FRenderCell := S.RenderCell;
  FEventCount := Min(S.EventCount, FEventCount);
  FAYTickT := S.AYTickT;
  FSamplePos := S.SamplePos;
  FPrevRegs := S.PrevRegs;
  FPrevPaging := S.PrevPaging;
  FStepCount := S.StepCount;
  Move(S.PortLog, FPortLog, SizeOf(FPortLog));
  FPortLogPos := S.PortLogPos;
  FPortLogCount := S.PortLogCount;
  UpdatePaging;
  FBreakHit := False;
  FBreakKind := bkNone;
  FBreakReason := '';
end;

function TSpectrum.PagingState: TPagingState;
var
  I: Integer;
begin
  for I := 0 to 3 do Result.Slots[I] := FSlotBank[I];
  Result.DivActive := FDivOn and FDiv.Active;
  Result.DivMapped := FDiv.Mapped;
  Result.DivControl := FDiv.Control;
  Result.CurrahPaged := FCurrahOn and FCurrah.Paged;
  Result.UnoConf := FZXReg[0];
  Result.UnoMapper := FZXReg[1];
end;

procedure TSpectrum.SetTrackPrev(Value: Boolean);
begin
  // Until an instruction runs, "before the last instruction" is "now"
  if Value and not FTrackPrev then
  begin
    FPrevRegs := FCpu.GetRegs;
    FPrevPaging := PagingState;
  end;
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
  FUserSpeed := Value;
  // The Next's own turbo (NR 07) on top of it
  FPendingSpeed := Min(32, FUserSpeed * FNextSpeed);
end;

procedure TSpectrum.SetFastDisk(Value: Boolean);
begin
  FFDC.Timed := not Value;
  FWD.Timed := not Value;
end;

function TSpectrum.DiskAt(Drive: Integer): TDiskImage;
begin
  if FIsC64 then
  begin
    Drive := Drive and 1;
    Result := nil;
    if FC64.DiskAt(Drive) = nil then Exit;
    if FC64Shadow[Drive] = nil then FC64Shadow[Drive] := TDiskImage.Create;
    FC64Shadow[Drive].FileName := FC64.DiskAt(Drive).FileName;
    Exit(FC64Shadow[Drive]);
  end;
  if FIsSAM or FIsMSX then Result := FWD.Disk(Drive) else Result := FFDC.Disk(Drive);
end;

procedure TSpectrum.InsertDiskAt(Drive: Integer; Disk: TDiskImage);
begin
  if FIsC64 then Exit;       // (the C64's disks are .d64 images: TC64.InsertDisk)
  if FIsSAM or FIsMSX then FWD.InsertDisk(Drive, Disk) else FFDC.InsertDisk(Drive, Disk);
end;

function TSpectrum.EjectDiskAt(Drive: Integer): TDiskImage;
begin
  if FIsSAM or FIsMSX then Result := FWD.EjectDisk(Drive) else Result := FFDC.EjectDisk(Drive);
end;

function TSpectrum.DiskLastAccess(Drive: Integer): QWord;
begin
  if FIsC64 then Exit(FC64.Drive[Drive].LastAccess);
  if FIsSAM or FIsMSX then Result := FWD.LastAccess(Drive) else Result := FFDC.LastAccess(Drive);
end;

function TSpectrum.GetDriveB: Boolean;
begin
  if FIsC64 then Exit(FC64.DriveOn[1]);
  if FIsSAM or FIsMSX then Result := FWD.DriveB else Result := FFDC.DriveB;
end;

procedure TSpectrum.SetDriveB(Value: Boolean);
begin
  if FIsC64 then
  begin
    FC64.SetDriveEnabled(1, Value);
    Exit;
  end;
  FFDC.DriveB := Value;
  FWD.DriveB := Value;
end;

function TSpectrum.GetFastDisk: Boolean;
begin
  Result := not FFDC.Timed;
end;

procedure TSpectrum.RenderToCurrent;
begin
  RenderUpTo(U(FCpu.T));
  if FIsCPC then FCPC.PreviewFrame;
  if FIsMSX then FMsxHw.PreviewFrame;
end;

function TSpectrum.SetSlot3Bank(Bank: Integer): Boolean;
begin
  Result := not (FInfo.Memory in [mk48K, mkCPC, mkSAM]) and ((FPort1FFD and 1) = 0);
  if not Result then Exit;
  FPort7FFD := (FPort7FFD and $F8) or (Bank and 7);
  UpdatePaging;
end;

function TSpectrum.CPCSlotCanHold(Slot, What: Integer): Boolean;
begin
  if FIsSAM then Exit(SamSlotCanHold(Slot, What));
  Result := FIsCPC and FCPC.SlotCanHold(Slot, What);
end;

function TSpectrum.SetCPCSlot(Slot, What: Integer): Boolean;
begin
  if FIsSAM then Exit(SetSamSlot(Slot, What));
  Result := FIsCPC and FCPC.SetSlot(Slot, What);
  if Result then CPCPaging;
end;

function TSpectrum.PagedRom: Integer;
begin
  Result := CurrentRom;
end;

function TSpectrum.MemoryAt(Addr: Word): TMemoryAt;
var
  Bank: Integer;
begin
  if FIsC64 then
  begin
    case FC64.MemoryAt(Addr) of
      1, 2, 3: Result := maRom;
    else
      Result := maRam;
    end;
    Exit;
  end;
  // The DivMMC paged in at 0000-3FFF: its EEPROM (or write-protected bank)
  // is like ROM, its RAM at 2000-3FFF is RAM
  if FDivOn and (Addr < $4000) and FDiv.Active then
  begin
    if FDiv.ReadOnlyAt(Addr) then Result := maRom else Result := maRam;
    Exit;
  end;
  if FCurrahOn and FCurrah.Paged and (Addr < $1000) then Exit(maRom);
  if IsNext then
  begin
    if FNextMMU[Addr shr 13] < NEXT_PAGES then Result := maRam
    else if (Addr < $4000) and (FNextMMU[Addr shr 13] = 255) then Result := maRom
    else Result := maNone;
    Exit;
  end;
  Bank := FSlotBank[Addr shr 14];
  if Bank = NO_MEMORY then Result := maNone
  else if Bank < 0 then Result := maRom
  else Result := maRam;
end;

procedure TSpectrum.Poke(Addr: Word; Value: Byte);
begin
  if FIsC64 then
  begin
    FC64.Poke(Addr, Value);
    Exit;
  end;
  case MemoryAt(Addr) of
    maNone: Exit;
    maRom: if not RomWritable then Exit;
  end;
  if FDivOn and (Addr < $4000) and FDiv.Active then FDiv.ForceWrite(Addr, Value)
  else FPage[Addr shr 13][Addr and $1FFF] := Value;
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
  // The Next keeps the chip chosen when TurboSound is switched off ("frozen",
  // turbosound.vhd); it can only be changed with TurboSound on
  case FAYChip of
    1: if TurboOn or IsNext then Result := FAY2 else Result := FAY;
    2: if IsNext then Result := FAY3 else Result := FAY;
  else
    Result := FAY;
  end;
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
  // The MSX has no contention (its wait states are on the M1 and I/O cycles): an opcode fetch (the only
  // 4 T-state access) is held for one more, as on the real machine; loaders that read a tape signal count on it
  if FIsMSX then
  begin
    Inc(T, Time);
    if Time = 4 then Inc(T);
    Exit;
  end;
  // The CPC: the Gate Array holds every memory access to the 1 MHz grid
  if FIsCPC then
  begin
    Inc(T, Time);
    if FContend then T := (T + 3) and not 3;
    Exit;
  end;
  // The SAM Coupe's ASIC holds the CPU's RAM accesses to its memory slots (the ROM is free)
  if FIsSAM then
  begin
    if FContend and (FSlotBank[Addr shr 14] >= 0) then Inc(T, FSam.WaitStates(T));
    Inc(T, Time);
    Exit;
  end;
  if FContend and FSlotContended[Addr shr 14] then Inc(T, FContention[T]);
  Inc(T, Time);
end;

procedure TSpectrum.ContendNoMreq(Addr: Word; Time: Integer; var T: Integer);
begin
  if FIsCPC or FIsMSX then
  begin
    Inc(T, Time);
    Exit;
  end;
  if FInfo.NoMreqContention and FContend and FSlotContended[Addr shr 14] then
    Inc(T, FContention[T]);
  Inc(T, Time);
end;

{ 0000-3FFF without the DivMMC paged in: the Spectrum's ROM, or the Currah
  µSpeech's (any access to 0038 toggles it, after the access) }
function TSpectrum.LowRead(Addr: Word; T: Integer): Byte;
begin
  if not FCurrahOn then Exit(FPage[Addr shr 13][Addr and $1FFF]);
  if FCurrah.Paged and (Addr < $1000) then Result := FCurrah.ReadRom(Addr)
  else if FCurrah.Paged and (Addr = $1000) then Result := FCurrah.ReadStatus(U(T))
  else Result := FPage[Addr shr 13][Addr and $1FFF];
  if Addr = $0038 then FCurrah.Toggle;
end;

function TSpectrum.ReadMem(Addr: Word; T: Integer): Byte;
var
  L2: Integer;
begin
  if FIsCPC then Exit(ReadMemCPC(Addr));
  if FIsMSX then Exit(ReadMemMSX(Addr));
  // The Next's Layer 2 mapped over the bottom of memory (port 123B), under
  // the DivMMC (the Next decodes 0000-3FFF: boot ROM, configuration
  // mapping, Multiface, DivMMC, Layer 2, MMU)
  if IsNext and ((FNextL2Port and 4) <> 0) and not ((Addr < $4000) and (FDiv.Active or FMfOn)) and
     not FNextBootOn and NextL2Bank(Addr, False, L2) then
    Result := FRam[L2][Addr and $3FFF]
  else if FDivOn and (Addr < $4000) and FDiv.Active then
    Result := FDiv.Read(Addr)
  else if Addr < $4000 then
    Result := LowRead(Addr, T)
  else
    Result := FPage[Addr shr 13][Addr and $1FFF];
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
  IPC: Word;
  SP: Word;
  Z80Block: Boolean;

  procedure AddEntry(Header: Word);
  begin
    FDaadEntries[FDaadEntryPos] := Header;
    FDaadEntryPos := (FDaadEntryPos + 1) mod DAAD_ENTRY_HISTORY;
    if FDaadEntryCount < DAAD_ENTRY_HISTORY then Inc(FDaadEntryCount);
  end;

begin
  if FIsC64 then
  begin
    IPC := FC64.Cpu.InstrPC;
    SP := $0100 or FC64.Cpu.SP;
    Z80Block := False;
  end
  else
  begin
    IPC := FInstrPC;
    SP := FCpu.SP.W;
    Z80Block := Peek(IPC) = $ED;      // (LDIR and the like copy data: never the interpreter's fetch)
  end;
  if (FDaadMap[Addr] and DAAD_ENTRY) <> 0 then
  begin
    if FDaadEntryPC >= 0 then
    begin
      // The interpreter takes the address of an entry's condacts: it runs it
      if IPC = FDaadEntryPC then AddEntry(Word(Addr - 2));
    end
    else if not Z80Block then
    begin
      FDaadCandEntryPC := IPC;
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
    if (Addr <> FDaadExpect) or Z80Block then Exit;
    FDaadExpect := -1;
    if (FDaadSeen > 0) and (IPC = FDaadCandFetchPC) then Inc(FDaadSeen) else FDaadSeen := 1;
    FDaadCandFetchPC := IPC;
    if FDaadSeen < 2 then Exit;
    FDaadFetchPC := IPC;
    FDaadEntryPC := FDaadCandEntryPC;
    AddEntry(FDaadCandHeader);
  end
  else if IPC <> FDaadFetchPC then
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
  if (FDaadStop = dsNext) or ((FDaadStop = dsOver) and (SP >= FDaadSP)) then
  begin
    // Stops after the instruction that read it
    FDaadStop := dsNone;
    if FIsC64 then
    begin
      FC64.BreakHit := True;
      FC64.BreakKind := cbkDaad;
    end;
    FBreakHit := True;
    FBreakKind := bkDaad;
    FBreakInstr := IPC;
    FBreakReason := '';
  end;
end;

{ Flag N of the game: IX points at the flags while a condact runs }
function TSpectrum.DaadFlag(N: Byte): Byte;
begin
  Result := PeekRam(Word(DaadFlagsBase + N));
end;

{ Where the interpreter keeps the flags: IX points at them on the Z80 machines, and they are at a fixed place on the C64 }
function TSpectrum.DaadFlagsBase: Word;
begin
  if FIsC64 then Result := C64_DAAD_FLAGS else Result := FCpu.IX.W;
end;

function TSpectrum.DaadStackPointer: Word;
begin
  if FIsC64 then Result := $0100 or FC64.Cpu.SP else Result := FCpu.SP.W;
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
  if FIsC64 then FC64.SetDaadMap(Map);
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
  if FIsCPC then Exit(FCPC.Read(Addr));
  if FIsMSX then Exit(FMsxHw.Read(Addr));
  // Opcode fetches never trigger read breakpoints
  // The Next's Multiface pages in as its NMI fetches 0066
  if FMfNmi and (Addr = $0066) and not FMfOn then
  begin
    FMfOn := True;
    NextUpdatePaging;
  end;
  if FDivOn and (Addr < $4000) then
  begin
    // DivMMC automatic paging happens around opcode fetches
    FDiv.BeforeFetch(Addr);
    if FDiv.Active then Result := FDiv.Read(Addr) else Result := LowRead(Addr, T);
    FDiv.AfterFetch(Addr);
  end
  else if Addr < $4000 then
    Result := LowRead(Addr, T)
  else
    Result := FPage[Addr shr 13][Addr and $1FFF];
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
  if FIsC64 then Exit(FC64.Peek(Addr));
  if FIsMSX then Exit(FMsxHw.Peek(Addr));
  if FDivOn and (Addr < $4000) and FDiv.Active then
    Result := FDiv.Read(Addr)
  else if FCurrahOn and FCurrah.Paged and (Addr < $1000) then
    Result := FCurrah.ReadRom(Addr)
  else
    Result := FPage[Addr shr 13][Addr and $1FFF];
end;

procedure TSpectrum.WriteMem(Addr: Word; Value: Byte; T: Integer);
var
  Slot: Integer;
begin
  if FIsCPC then
  begin
    WriteMemCPC(Addr, Value);
    Exit;
  end;
  if FIsMSX then
  begin
    WriteMemMSX(Addr, Value);
    Exit;
  end;
  Slot := Addr shr 14;
  if IsNext and ((FNextL2Port and 1) <> 0) and not ((Addr < $4000) and (FDiv.Active or FMfOn)) and
     not FNextBootOn and NextL2Bank(Addr, True, Slot) then
  begin
    FRam[Slot][Addr and $3FFF] := Value;
    Exit;
  end;
  if (FMemBreakpoints > 0) and not FSuppressBreaks and
     ((FBreakFlags[Addr] and (BP_WRITE or BP_DISABLED)) = BP_WRITE) and ConditionHolds(Addr) then
  begin
    FBreakHit := True;
    FBreakKind := bkMemory;
    FBreakInstr := FInstrPC;
    FBreakReason := Format('Write breakpoint at %.4X (instruction at %.4X)', [Addr, FInstrPC]);
  end;
  if FCurrahOn and (Addr < $4000) then
  begin
    // The µSpeech: 1000 an allophone, 3000/3001 the intonation
    FCurrah.Write(Addr, Value, U(T));
    if Addr = $0038 then FCurrah.Toggle;
  end;
  if FDivOn and (Addr < $4000) and FDiv.Active then
  begin
    FDiv.Write(Addr, Value);
    Exit;
  end;
  Slot := Addr shr 13;
  if FPageRO[Slot] then
  begin
    // The Next's alternate ROM can be written through the ROM's addresses
    if IsNext and (Addr < $4000) and (FNextMMU[Slot] = 255) and ((FNextReg[$8C] and $C0) = $C0) then
      FNextSram[6 + NextAltRomIndex][Addr] := Value;
    Exit;  // ROM
  end;
  if FPageScreen[Slot] and ((Addr and $1FFF) < 6912) then
  begin
    // The Next draws whole lines then (a split for every write would be slow)
    if IsNext then NextRenderUpTo(U(T), False) else RenderUpTo(U(T));
  end;
  FPage[Slot][Addr and $1FFF] := Value;
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
  if FIsCPC then Exit(ReadPortCPC(Port, T));
  if FIsSAM then Exit(ReadPortSAM(Port, T));
  if FIsMSX then Exit(ReadPortMSX(Port, T));
  IOContendPre(Port, T);
  Result := $FF;
  Responded := False;
  if FCurrahOn and (Port = $0038) then FCurrah.Toggle;

  if IsNext and NextMfPortRead(Port, HighByte) then
  begin
    Responded := True;
    Result := HighByte;
  end
  else if IsNext and (((Port and $FF) = $6B) or ((Port and $FF) = $0B)) then
  begin
    Responded := True;
    Result := DmaRead;
  end
  else if (Port and 1) = 0 then
  begin
    // ULA: keyboard, EAR
    Responded := True;
    HighByte := Port shr 8;
    for Row := 0 to 7 do
      if (HighByte and (1 shl Row)) = 0 then Result := Result and KeyRow(Row);
    Result := Result or $A0;
    FTape.AdvanceTo(T);
    Inc(FTapeReads);
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
  else if IsNext and ((Port and $FF) = $EB) and ((FNextSpiCS and $80) = 0) then
  begin
    Responded := True;
    Result := NextFlashRead;
  end
  else if IsNext and ((Port and $FF) = $E7) then
  begin
    Responded := True;
    Result := FNextSpiCS;
  end
  else if FDivOn and FDiv.IsPort(Port) then
  begin
    Responded := True;
    Result := FDiv.ReadPort(Port);
  end
  // The Next's second Kempston joystick (port 37): none plugged in, so
  // nothing pressed (games read both and join them; FF would hold every
  // direction and fire)
  else if IsNext and ((Port and $FF) = $37) then
  begin
    Responded := True;
    Result := 0;
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
    MouseReadTick := GetTickCount64;
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

  if IsNext and (Port = $243B) then
  begin
    Responded := True;
    Result := FNextSel;
  end
  else if IsNext and (Port = $253B) then
  begin
    Responded := True;
    Result := NextReadReg(FNextSel);
  end
  else if IsNext and (Port = $123B) then
  begin
    Responded := True;
    Result := FNextL2Port;
  end
  else if IsNext and (Port = $303B) then
  begin
    Responded := True;
    Result := FSprStatus;
    FSprStatus := 0;
  end
  else if IsNext and (Port = $BFF5) then
  begin
    // AY info: the active chip and its selected register
    Responded := True;
    Result := ((3 - FAYChip) shl 6) or (ActiveAY.Selected and $1F);
  end
  else if IsZXUno and (Port = $FC3B) then
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
  if FIsCPC then
  begin
    WritePortCPC(Port, Value, T);
    Exit;
  end;
  if FIsSAM then
  begin
    WritePortSAM(Port, Value, T);
    Exit;
  end;
  if FIsMSX then
  begin
    WritePortMSX(Port, Value, T);
    Exit;
  end;
  IOContendPre(Port, T);
  LogPort(Port, Value, True);
  CheckPortBreak(Port, True);
  if FCurrahOn and (Port = $0038) then FCurrah.Toggle;
  if IsNext then NextMfPortWrite(Port);

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

  if IsNext and ((Port and $FF) = $E7) then
  begin
    // One device at a time: the SD card only when it alone is chosen
    FNextSpiCS := Value;
    FNextFlashIdx := 0;
    FNextFlashReads := 0;
    if (Value and $8F) = $8E then FDiv.WritePort(Port, Value) else FDiv.WritePort(Port, $FF);
  end
  else if IsNext and ((Port and $FF) = $EB) and ((FNextSpiCS and $80) = 0) then
    NextFlashWrite(Value)
  else if FDivOn and FDiv.IsPort(Port) then
    FDiv.WritePort(Port, Value);

  if IsNext and (Port = $243B) then
    FNextSel := Value
  else if IsNext and (Port = $253B) then
  begin
    NextRenderUpTo(U(T), NextVideoReg(FNextSel));
    NextWriteReg(FNextSel, Value);
  end
  else if IsNext and (Port = $123B) then
  begin
    RenderUpTo(U(T));
    if (Value and $10) <> 0 then FNextL2Offset := Value and 7 else FNextL2Port := Value;
  end
  else if IsNext and (Port = $303B) then
  begin
    FSprIndex := Value and 127;
    FSprAttrIdx := 0;
    FSprPatAddr := (Value and $3F) * 256 + (Value shr 7) * 128;
  end
  else if IsNext and ((Port and $FF) = $57) then
    NextSpriteAttr(Value)
  else if IsNext and (((Port and $FF) = $6B) or ((Port and $FF) = $0B)) then
    DmaWrite(Value)
  else if IsNext and ((FNextReg[$08] and 8) <> 0) and
    ((Port and $FF) in [$1F, $F1, $3F, $0F, $F3, $DF, $FB, $B3, $4F, $F9, $5F]) then
    NextDacWrite(Port, Value, U(T))
  else if IsNext and ((Port and $FF) = $5B) then
  begin
    FSprPattern[FSprPatAddr] := Value;
    FSprPatAddr := (FSprPatAddr + 1) and $3FFF;
  end;

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
    mkZXNext:
      // 7FFD (+3 decoding), DFFD and 1FFD; DFFD wins over the AY's FFFD
      if (Port and $F003) = $D001 then
      begin
        FPortDFFD := Value and $0F;
        NextPortPaging(True);
      end
      else if (Port and $C003) = $4001 then
      begin
        if (FPort7FFD and $20) = 0 then
        begin
          RenderUpTo(U(T));
          FPort7FFD := Value;
          NextPortPaging(True);
        end;
      end
      else if (Port and $F003) = $1001 then
      begin
        if (FPort7FFD and $20) = 0 then
        begin
          FPort1FFD := Value;
          NextPortPaging(True);
        end;
      end;
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

  if HasAY and not (IsNext and ((Port and $F003) = $D001)) then
  begin
    if (Port and $C002) = $C000 then
    begin
      if TurboOn and ((Value and $9C) = $9C) then
      begin
        // $FF: first chip, $FE: second; the Next's third is $FD, and bits
        // 6-5 switch the chip's left and right outputs
        if IsNext and ((Value and 3) <> 0) then
        begin
          FAYChip := 3 - (Value and 3);
          FAYPan[FAYChip] := (Value shr 5) and 3;
        end
        else if (Value and 3) >= 2 then
          FAYChip := (not Value) and 1;
      end
      else
        ActiveAY.SelectRegister(Value);
    end
    else if (Port and $C002) = $8000 then
    begin
      if ActiveAY.Selected < 16 then
        if ActiveAY = FAY3 then AddEvent(U(T), 4, ActiveAY.Selected, Value)
        else AddEvent(U(T), 1 + Ord(ActiveAY = FAY2), ActiveAY.Selected, Value);
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
  if IsZXUno then Result := (FZXReg[$0F] and 1) = 0
  else if IsNext then Result := (FNextReg[$68] and 8) <> 0
  else Result := ULAPlusEnabled;
end;

function TSpectrum.HasTimex: Boolean;
begin
  if IsZXUno then Result := (FZXReg[$0F] and 2) = 0
  else if IsNext then Result := True
  else Result := TimexEnabled;
end;

function TSpectrum.HasRadastan: Boolean;
begin
  if IsZXUno then Result := (FZXReg[$0F] and 4) = 0
  else if IsNext then Result := False
  else Result := RadastanEnabled;
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
  if FIsCPC then Exit(FCPC.IntLine);
  if FIsSAM then Exit(FSam.InterruptActive(U(FCpu.T)));
  if FIsMSX then Exit(FMsxHw.IntLine);
  if IsNext then
  begin
    // ULA interrupt unless NR 22 (or port FF bit 6) disables it, and the
    // line interrupt
    Result := (FCpu.T < FInfo.InterruptLength * FSpeed) and ((FNextReg[$22] and 4) = 0) and
      ((FTimexPort and $40) = 0);
    if not Result and ((FNextReg[$22] and 2) <> 0) then Result := NextLineIntActive;
  end
  else if IsZXUno then
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
    raise Exception.CreateFmt(_('ZX-Uno BIOS not found: %s'), [Firmware]);
  if not FileExists(Roms) then
    raise Exception.CreateFmt(_('ZX-Uno ROMs not found: %s'), [Roms]);
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
  // TZX's "stop the tape if in 48K mode"
  FTape.StopIf48K := FModel in [sm16K, sm48K];
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
        // SCANDBLCTRL: bits 6-7 the CPU speed (3.5, 7, 14, 28 MHz), on top
        // of the speed setting
        FZXReg[$0B] := Value;
        FNextSpeed := 1 shl ((Value shr 6) and 3);
        SetSpeed(FUserSpeed);
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
  CORE_ID = 'ochenta-ZXUno';
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
  if FIsC64 then Exit;      // the VIC-II draws as it goes
  if FIsCPC then
  begin
    if T > FInfo.FrameT then T := FInfo.FrameT;
    FCPC.Sync(T);
    Exit;
  end;
  if FIsSAM then
  begin
    SAMRenderUpTo(T);
    Exit;
  end;
  if FIsMSX then
  begin
    if T > MSX_FRAME_T then T := MSX_FRAME_T;
    FMsxHw.Sync(T);
    Exit;
  end;
  if IsNext then
  begin
    NextRenderUpTo(T, True);
    Exit;
  end;
  while FRenderLine < SCREEN_HEIGHT do
  begin
    // T-state at which this 8-pixel cell is displayed. It takes its data
    // (screen bytes, border colour) at the end of its 4 T-states, as Fuse
    // does: a write or OUT up to then still changes it (multicolour and
    // border effects that race the beam depend on it)
    CellT := FInfo.PaperTopT + (FRenderLine - BORDER_TOP) * FInfo.LineT - BORDER_LEFT div 2 +
      FRenderCell * 4;
    if CellT + 4 > T then Exit;
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
  FNextDrawnX := 0;
  FRenderCell := 0;
end;

procedure TSpectrum.CopyFrameBuffer(Dest: PLongWord);
begin
  if FIsC64 then
  begin
    FC64.CopyFrame(Dest);
    Exit;
  end;
  if FIsCPC then
  begin
    FCPC.CopyFrame(Dest);
    Exit;
  end;
  if FIsMSX then
  begin
    FMsxHw.CopyFrame(Dest);
    Exit;
  end;
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

{ The tape runs in CPU T-states, so that its pulses keep their length for
  the ROM's loader at any CPU speed (it just plays faster); the sound is in
  frame T-states }
procedure TSpectrum.TapeEdge(T: Integer; Level: Boolean);
begin
  // The CPC: its tape runs in 3.5 MHz T-states (CPCTapeT); the signal is heard, as the Spectrum's EAR
  // is (the cassette's sound through the speaker)
  if FIsMSX then
  begin
    MSXBeeper(Int64(T) * 3579545 div (Int64(3500000) * FSpeed));
    Exit;
  end;
  if FIsCPC then
  begin
    if FTape.Playing and Level then AddEvent(T * 8 div (7 * FSpeed), 0, 0, 2)
    else AddEvent(T * 8 div (7 * FSpeed), 0, 0, 0);
    Exit;
  end;
  UpdateBeeper(U(T));
end;

function BeeperValue(Level: Byte): Single; inline;
begin
  Result := 0;
  if (Level and 2) <> 0 then Result := Result + 0.75;   // EAR
  if (Level and 1) <> 0 then Result := Result + 0.08;   // MIC
  if (Level and 4) <> 0 then Result := Result + 0.25;   // tape
end;

procedure TSpectrum.ApplyEvent(Index: Integer);
var
  K: Integer;
begin
  case FEvents[Index].Kind of
    0: FBeeperLevel := FEvents[Index].Value;
    1: FAY.WriteRegister(FEvents[Index].Reg, FEvents[Index].Value);
    2: FAY2.WriteRegister(FEvents[Index].Reg, FEvents[Index].Value);
    4: FAY3.WriteRegister(FEvents[Index].Reg, FEvents[Index].Value);
    5: FSaa.WriteRegister(FEvents[Index].Reg, FEvents[Index].Value);
    3:
      for K := 0 to 3 do
        if (FEvents[Index].Reg and (1 shl K)) <> 0 then FNextDac[K] := FEvents[Index].Value;
  end;
end;

{ The Next: one AY chip's channels into the left and right outputs }
procedure TSpectrum.AddAY(Chip: Integer; const Lv: array of Single; Gain: Single; var L, R: Single);
var
  CL, CR, Mono: Single;
begin
  // TurboSound off: only the chip chosen last is heard
  if not TurboOn and (Chip <> FAYChip) then Exit;
  if (FNextReg[$09] and ($20 shl Chip)) <> 0 then
  begin
    Mono := (Lv[0] + Lv[1] + Lv[2]) * 0.5 * Gain;
    CL := Mono;
    CR := Mono;
  end
  else if (FNextReg[$08] and $20) <> 0 then
  begin
    // ACB: B on the right, C in the middle
    CL := (Lv[0] * 0.75 + Lv[2] * 0.5 + Lv[1] * 0.25) * Gain;
    CR := (Lv[1] * 0.75 + Lv[2] * 0.5 + Lv[0] * 0.25) * Gain;
  end
  else
  begin
    CL := (Lv[0] * 0.75 + Lv[1] * 0.5 + Lv[2] * 0.25) * Gain;
    CR := (Lv[2] * 0.75 + Lv[1] * 0.5 + Lv[0] * 0.25) * Gain;
  end;
  if (FAYPan[Chip] and 2) <> 0 then L := L + CL;
  if (FAYPan[Chip] and 1) <> 0 then R := R + CR;
end;

procedure TSpectrum.GenerateAudio;
var
  TPerSample, Pos, EndT, NextT, Acc: Double;
  EvIndex, Ch, TickCount, K: Integer;
  Drive, Spinning, Reading: Boolean;
  Clicks: TInt64DynArray;
  ClickLen: Int64;
  Floppy, Steps: Single;
  TickA, TickB, TickC, A, B, C, A2, B2, C2, A3, B3, C3, L, R, AYGain, SaaL, SaaR: Single;
  DacL, DacR: Integer;
  Two, Three: Boolean;
  Mix: array[0..1] of Single;
begin
  TPerSample := FInfo.ClockHz / SAMPLE_RATE;
  // The Next always runs its three chips (only the selected one is heard
  // with TurboSound off); TurboSound elsewhere adds the second
  if IsNext then
  begin
    Two := HasAY;
    Three := HasAY;
  end
  else
  begin
    Two := TurboOn and HasAY;
    Three := False;
  end;
  // Floppy drive noise: only with the drive at real speed
  Drive := FloppyNoise and FInfo.HasFDC and FFDC.Timed and
    ((FFDC.Disk(0) <> nil) or (FFDC.Disk(1) <> nil));
  if Drive then
  begin
    ClickLen := Round(FInfo.ClockHz * STEP_EXCITE_SECS);
    Clicks := FFDC.StepTimes(FrameStartT - ClickLen, FrameStartT + FInfo.FrameT);
    Spinning := FFDC.Motor;
    Reading := FFDC.HeadActive;
  end;
  // One chip heard (the Next with TurboSound off too) is as loud as before
  if IsNext and not TurboOn then AYGain := 0.35
  else if Three then AYGain := 0.2
  else if Two then AYGain := 0.25
  else AYGain := 0.35;
  if FCurrahOn then
  begin
    FCurrah.ClockHz := FInfo.ClockHz;
    FCurrah.Sync(FInfo.FrameT);
  end;
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
    A3 := 0; B3 := 0; C3 := 0;
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
          if Three then
          begin
            FAY3.Tick(TickA, TickB, TickC);
            A3 := A3 + TickA; B3 := B3 + TickB; C3 := C3 + TickC;
          end;
          Inc(TickCount);
          Inc(FAYTickT, FAYStep);
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
      FAY3Levels[0] := A3 / TickCount;
      FAY3Levels[1] := B3 / TickCount;
      FAY3Levels[2] := C3 / TickCount;
    end;
    if not HasAY then
    begin
      FAYLevels[0] := 0; FAYLevels[1] := 0; FAYLevels[2] := 0;
    end;
    if not Two then
    begin
      FAY2Levels[0] := 0; FAY2Levels[1] := 0; FAY2Levels[2] := 0;
    end;
    if not Three then
    begin
      FAY3Levels[0] := 0; FAY3Levels[1] := 0; FAY3Levels[2] := 0;
    end;
    L := Acc * 0.5;
    R := Acc * 0.5;
    if IsNext then
    begin
      // Each chip ABC or ACB stereo (NR 08 bit 5), or mono (NR 09 bits 5-7),
      // with the outputs port FFFD left on
      AddAY(0, FAYLevels, AYGain, L, R);
      AddAY(1, FAY2Levels, AYGain, L, R);
      AddAY(2, FAY3Levels, AYGain, L, R);
    end
    else
    begin
      // ABC stereo
      L := L + (FAYLevels[0] * 0.75 + FAYLevels[1] * 0.5 + FAYLevels[2] * 0.25 +
        FAY2Levels[0] * 0.75 + FAY2Levels[1] * 0.5 + FAY2Levels[2] * 0.25) * AYGain;
      R := R + (FAYLevels[2] * 0.75 + FAYLevels[1] * 0.5 + FAYLevels[0] * 0.25 +
        FAY2Levels[2] * 0.75 + FAY2Levels[1] * 0.5 + FAY2Levels[0] * 0.25) * AYGain;
    end;
    if IsNext then
    begin
      // The Next's DACs: A and B on the left, C and D on the right
      DacL := Integer(FNextDac[0]) + Integer(FNextDac[1]) - 256;
      DacR := Integer(FNextDac[2]) + Integer(FNextDac[3]) - 256;
      L := L + DacL * (1 / 512);
      R := R + DacR * (1 / 512);
    end;
    if FIsSAM then
    begin
      // The SAA1099, always running so its registers keep their meaning; heard if it is on
      FSaa.Sample(SAMPLE_RATE, SaaL, SaaR);
      if FSamSaaOn then
      begin
        L := L + SaaL * 0.15;
        R := R + SaaR * 0.15;
      end;
    end;
    if FCurrahOn then
    begin
      // The µSpeech's voice, mixed in with the Spectrum's sound on the TV
      Floppy := FCurrah.Level(EndT) * 2.5;
      L := L + Floppy;
      R := R + Floppy;
    end;
    if Drive then
    begin
      // The motor, the head on the disk and the steps' knocks (FloppySound)
      Steps := 0;
      for K := 0 to High(Clicks) do
        Steps := Steps + FFloppySound.StepExcite((FrameStartT + Round(Pos) - Clicks[K]) / FInfo.ClockHz, False);
      Floppy := 0.8 * FFloppySound.Sample(Spinning, Reading, Steps, 0);
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
  if FCurrahOn then FCurrah.EndFrame(FInfo.FrameT);
  FSamplePos := FSamplePos - FInfo.FrameT;
  Dec(FAYTickT, FInfo.FrameT);
end;

function TSpectrum.Samples: Pointer;
begin
  Result := @FSamples[0];
end;

{ Tape traps }

function TSpectrum.TapeAccelerating: Boolean;
begin
  // (not the CPC's: it has no ROM trap, so its tapes would all run mute and fast; loaders that play music
  // while they load, and the tones, are heard at the real speed: Turbo is there for the impatient)
  if FIsC64 then Exit(FastLoad and FC64.TapePressed and FC64.TapeMotor);
  Result := FastLoad and FTape.Playing and not FIsCPC;
end;

function TSpectrum.DiskAccelerating: Boolean;
begin
  if FIsC64 then Exit(not FFDC.Timed and FC64.DriveBusy and (GetTickCount64 - FC64.DiskActivity < 300));
  // The drive was used in the last tenth of a second
  Result := (FIsSAM or FIsMSX) and not FWD.Timed and
    ((GetTickCount64 - FWD.LastAccess(0) < 100) or (GetTickCount64 - FWD.LastAccess(1) < 100)) and
    (FWD.Disk(0) <> nil);
end;

procedure TSpectrum.TapeTrap;
var
  Block: TTapeBlock;
  Len, N, I: Integer;
  Parity: Byte;
  Ok, Loading: Boolean;
  Addr: Word;
begin
  // Where a playing tape is now, so the right block is taken
  FTape.AdvanceTo(FCpu.T);
  Block := FTape.TakeBlockForTrap;
  if Block = nil then
  begin
    // The next block is one the ROM can't read (turbo data, from a .tzx):
    // it plays in real time
    if not FTape.Playing and (FTape.Current < FTape.Count) then FTape.Play(FCpu.T);
    Exit;
  end;
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
  // Turbo data next (a .tzx): the tape goes on, for the game's own loader
  if FTape.NextNeedsRealTime then FTape.Play(FCpu.T);
end;

{ Fast loading switched on while the ROM loads a block in real time: the
  rest of it at once. At LD-MARKER (05C8), about to read a byte: the flag (B
  = B0; A' holds the one wanted) or data (B = B2; H holds the parity so far).
  DE data bytes are left, then the parity byte; IX is where the next goes,
  F' carry says load (or verify). }
procedure TSpectrum.TapeTrapRest;
var
  Block: TTapeBlock;
  Pos, Len, N: Integer;
  Parity, B: Byte;
  Ok, Loading: Boolean;
  Addr: Word;
begin
  FTape.AdvanceTo(FCpu.T);
  Block := FTape.TakeBlockBeingRead(Pos);
  if Block = nil then Exit;
  Loading := (FCpu.F_ and FLAG_C) <> 0;
  Ok := True;
  Parity := FCpu.HL.H;
  if FCpu.BC.H = $B0 then
  begin
    // The flag byte, still to be read
    Ok := (Pos < Length(Block.Data)) and (Block.Data[Pos] = FCpu.A_);
    if Ok then Parity := Block.Data[Pos];
    Inc(Pos);
  end;
  Len := FCpu.DE.W;
  N := 0;
  while Ok and (N < Len) do
  begin
    if Pos >= Length(Block.Data) then
    begin
      Ok := False;
      Break;
    end;
    B := Block.Data[Pos];
    Addr := Word(FCpu.IX.W + N);
    Parity := Parity xor B;
    if Loading then
      WriteMem(Addr, B, FCpu.T)
    else if Peek(Addr) <> B then
    begin
      Ok := False;
      Break;
    end;
    Inc(N);
    Inc(Pos);
  end;
  // The parity byte: everything xor'ed together gives 0
  if Ok then Ok := (Pos < Length(Block.Data)) and ((Parity xor Block.Data[Pos]) = 0);
  FCpu.IX.W := Word(FCpu.IX.W + N);
  FCpu.DE.W := Word(FCpu.DE.W - N);
  if Ok then
    FCpu.F := FCpu.F or FLAG_C
  else
    FCpu.F := FCpu.F and not FLAG_C;
  FCpu.PC.W := $05E2;
  if FTape.NextNeedsRealTime then FTape.Play(FCpu.T);
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

procedure TSpectrum.NoteEsxdosCall;
const
  F_OPEN = $9A;

  { The ASCIIZ name at Addr if it looks like a game file's, else '' }
  function NameAt(Addr: Word): string;
  var
    I: Integer;
    C: Byte;
    Ext: string;
  begin
    Result := '';
    for I := 0 to 63 do
    begin
      C := Peek(Word(Addr + I));
      if C = 0 then Break;
      if (C < 32) or (C > 126) then Exit('');
      Result := Result + Chr(C);
    end;
    Ext := UpperCase(ExtractFileExt(Result));
    if (Ext <> '.TAP') and (Ext <> '.TZX') and (Ext <> '.Z80') and (Ext <> '.SNA') and
       (Ext <> '.DSK') then Exit('');
    // Without the folder ("/GAMES/COZUMEL.TAP")
    Result := ExtractFileName(StringReplace(Result, '/', PathDelim, [rfReplaceAll]));
  end;

var
  Ret: Word;
  Name: string;
begin
  // The function number is the byte after the RST 8
  Ret := Peek(FCpu.SP.W) or (Peek(Word(FCpu.SP.W + 1)) shl 8);
  if Peek(Ret) <> F_OPEN then Exit;
  // The name is at IX (programs) or HL (dot commands)
  Name := NameAt(FCpu.IX.W);
  if Name = '' then Name := NameAt(FCpu.HL.W);
  if Name <> '' then LastMediaFile := Name;
end;

procedure TSpectrum.CheckTraps;
begin
  if FIsSAM then
  begin
    SAMCheckTraps;
    Exit;
  end;
  if not BasicRomPaged then Exit;
  if FDivOn and FDiv.Active then Exit;   // the DivMMC firmware is running there
  case FCpu.PC.W of
    $04C2:
      if SaveToTape then TapeSaveTrap;
    $056C:
      // Fast loading takes the block even if the tape was started with Play
      // (the trap stops it), so Play doesn't turn it into real-time loading
      if FastLoad and FTape.HasMore then
        TapeTrap;
    $0580:
      // LD-LEADER, reading a pilot tone in real time, and fast loading has
      // just been switched on: the block at once (the stack is as at 056C)
      if FastLoad and FTape.Playing and (Peek($0580) = $06) and (Peek($0581) = $9C) then
        TapeTrap;
    $05C8:
      // LD-MARKER, about to read a byte in real time (from LD-DEC or
      // LD-SYNC), and fast loading has just been switched on: the rest at once
      if FastLoad and FTape.Playing and (Peek($05C4) = $1B) and (Peek($05C5) = $08) and
         (Peek($05C6) = $06) and (Peek($05C7) = $B2) and (Peek($05C8) = $2E) and (Peek($05C9) = $01) and
         ((FCpu.BC.H = $B0) or (FCpu.BC.H = $B2)) then
        TapeTrapRest;
    $0556:
      // LD-BYTES: a load, for sure; the tape starts (the one stopped by the
      // user, or by a TZX block, as well: this is a new load)
      if not FastLoad and AutoPlayTape then
      begin
        FTapeHeld := False;
        FLoadDemand := True;
        FLoadEnded := False;
        FDemandFrames := 0;
        FQuietFrames := 0;
        FLoadedSincePlay := True;
        if not FTape.Playing and FTape.HasMore then FTape.Play(FCpu.T);
      end;
    $05E2:
      // The end of LD-BYTES: the load is over, unless another follows at
      // once (a header, then its data): stopped a few frames later
      if AutoPlayTape and FLoadDemand then FLoadEnded := True;
  end;
end;

{ Automatic typing }

function TSpectrum.KeyRow(Row: Integer): Byte;
var
  K, J: Integer;
begin
  Result := Keyboard[Row];
  // The two-key keys, unless the Next is told not to (NR 68 bit 4)
  if (ExtKeys <> 0) and not (IsNext and ((FNextReg[$68] and $10) <> 0)) then
    for K := 0 to 15 do
      if (ExtKeys and (1 shl K)) <> 0 then
        for J := 0 to 1 do
          if EXT_KEYS[K, J] div 5 = Row then
            Result := Result and not (1 shl (EXT_KEYS[K, J] mod 5));
  if FAutoKeyPos < Length(FAutoKeys) then
    Result := Result and FAutoKeys[FAutoKeyPos].Rows[Row];
end;

procedure TSpectrum.AutoType(Frames: Integer; const Keys: array of Integer);
var
  N, I: Integer;
begin
  if FIsC64 then Exit;      // (the C64 types through its keyboard buffer: TypeText)
  N := Length(FAutoKeys);
  SetLength(FAutoKeys, N + 1);
  FAutoKeys[N].Frames := Frames;
  FillChar(FAutoKeys[N].Rows, SizeOf(FAutoKeys[N].Rows), $FF);
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
  if FIsC64 then Exit(FC64.Typing);
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
  if FIsC64 then
  begin
    Error := '';
    FC64.TypeText(StringReplace(Text, '\n', #13, [rfReplaceAll]));
    Exit(True);
  end;
  if FIsCPC then Exit(CPCTypeText(Text, Error));
  if FIsMSX then Exit(MSXTypeText(Text, Error));
  if FIsSAM then Exit(SAMTypeText(Text, Error));
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

function TSpectrum.TypeSymbol(const Sym: string; DryRun: Boolean): Boolean;
const
  // What each machine types with TypeText as it is
  ZX_PLAIN = '!@#$%&''()_<>;"=+-^:?/*,.';
  CPC_PLAIN = '-^@[]\;:,./!"#$%&''()_=|{}`+*<>?';
  MSX_PLAIN = '-=;'',./[]\`!@#$%^&*()_+:"<>?';
  // The Spectrum's extended mode: CAPS SHIFT + SYMBOL SHIFT, then SYMBOL SHIFT and the key
  ZX_EXTENDED = '[]{}|~\';
  ZX_EXTENDED_KEYS: array[1..Length(ZX_EXTENDED)] of Integer = (KEY_Y, KEY_U, KEY_F, KEY_G, KEY_S, KEY_A, KEY_D);
  // The MSX (international keyboard): SHIFT on the keys of the plain ones
  MSX_SHIFTED = '~|{}';
  MSX_SHIFTED_KEYS: array[1..Length(MSX_SHIFTED)] of Integer = (MSXK_GRAVE, MSXK_BACKSLASH, MSXK_LBRACKET,
    MSXK_RBRACKET);
  // ... and the ones of its character set with no key of their own, which go into the BIOS's keyboard buffer
  MSX_CODED: array[0..5] of string = ('ñ', 'Ñ', '¿', '¡', '¬', '·');
  MSX_CODES: array[0..5] of Byte = ($A4, $A5, $A8, $AD, $AA, $FA);
var
  Ch: Char;
  P, Key, Modifier: Integer;
  Put, Next: Word;
  Err: string;
begin
  if FIsMSX then
    for P := 0 to High(MSX_CODED) do
      if Sym = MSX_CODED[P] then
      begin
        // The buffer (KEYBUF, FBF0h, 40 bytes) and its pointers (PUTPNT, GETPNT): full, it can't
        Put := FMsxHw.Peek($F3F8) or (FMsxHw.Peek($F3F9) shl 8);
        Next := Put + 1;
        if Next >= $FC18 then Next := $FBF0;
        if Next = FMsxHw.Peek($F3FA) or (FMsxHw.Peek($F3FB) shl 8) then Exit(False);
        if not DryRun then
        begin
          FMsxHw.Write(Put, MSX_CODES[P]);
          FMsxHw.Write($F3F8, Lo(Next));
          FMsxHw.Write($F3F9, Hi(Next));
        end;
        Exit(True);
      end;
  if Length(Sym) <> 1 then Exit(False);
  Ch := Sym[1];
  if FIsC64 then
  begin
    // The signs the C64's keyboard makes (letters and digits the virtual keyboard sends as they are)
    Result := C64KeysForChar(Ch, Key, Modifier);
    if Result and not DryRun then FC64.TypeText(Ch);
  end
  else if FIsSAM then
  begin
    Result := SamKeysForChar(Ch, Key, Modifier);
    if Result and not DryRun then
    begin
      if Modifier >= 0 then SAMAutoType(4, [Modifier, Key]) else SAMAutoType(4, [Key]);
      SAMAutoType(6, []);
    end;
  end
  else if FIsCPC then
  begin
    Result := Pos(Ch, CPC_PLAIN) > 0;
    if Result and not DryRun then CPCTypeText(Ch, Err);
  end
  else if FIsMSX then
  begin
    P := Pos(Ch, MSX_SHIFTED);
    Result := (P > 0) or (Pos(Ch, MSX_PLAIN) > 0);
    if Result and not DryRun then
      if P > 0 then
      begin
        MSXAutoType(4, [MSXK_SHIFT, MSX_SHIFTED_KEYS[P]]);
        MSXAutoType(4, []);
      end
      else
        MSXTypeText(Ch, Err);
  end
  else
  begin
    P := Pos(Ch, ZX_EXTENDED);
    Result := (P > 0) or (Pos(Ch, ZX_PLAIN) > 0);
    if Result and not DryRun then
      if P > 0 then
      begin
        AutoType(4, [KEY_CAPS, KEY_SYM]);
        AutoType(8, []);
        AutoType(4, [KEY_SYM, ZX_EXTENDED_KEYS[P]]);
        AutoType(8, []);
      end
      else
        TypeText(Ch, Err);
  end;
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

procedure TSpectrum.AutoLoad(FromDisk: Boolean; C64Drive: Integer);
begin
  FMsxTapeStart := FIsMSX and not FromDisk;
  Reset(True);
  FTape.Rewind;
  CancelAutoType;
  if FIsC64 then
  begin
    FC64.AutoLoad(FromDisk, C64Drive);
    Exit;
  end;
  if FIsCPC then
  begin
    CPCAutoLoad(FromDisk);
    Exit;
  end;
  if FIsSAM then
  begin
    SAMAutoLoad(FromDisk);
    Exit;
  end;
  if FIsMSX then
  begin
    MSXAutoLoad(FromDisk);
    Exit;
  end;
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
  if FIsC64 then Exit(FC64.GetBreakpoint(Addr));
  Result := FBreakFlags[Addr];
end;

function TSpectrum.BreakRangeIndex(Addr: Word; Port: Boolean): Integer;
begin
  for Result := 0 to High(FBreakRanges) do
    if (FBreakRanges[Result].Port = Port) and (Addr >= FBreakRanges[Result].First) and
       (Addr <= FBreakRanges[Result].Last) then Exit;
  Result := -1;
end;

function TSpectrum.BreakRangeLast(Addr: Word; Port: Boolean): Word;
var
  R: Integer;
begin
  R := BreakRangeIndex(Addr, Port);
  if R >= 0 then Result := FBreakRanges[R].Last else Result := Addr;
end;

procedure TSpectrum.DeleteBreakRange(R: Integer);
var
  I: Integer;
begin
  for I := R to High(FBreakRanges) - 1 do FBreakRanges[I] := FBreakRanges[I + 1];
  SetLength(FBreakRanges, Length(FBreakRanges) - 1);
end;

procedure TSpectrum.SetBreakRange(First, Last: Word; Port: Boolean);
var
  A: Integer;
begin
  // Whatever breakpoints there were in it go (whole ranges, if they overlap)
  for A := First to Last do
    if Port then SetPortBreakpoint(A, 0) else SetBreakpoint(A, 0);
  if Last > First then
  begin
    SetLength(FBreakRanges, Length(FBreakRanges) + 1);
    FBreakRanges[High(FBreakRanges)].First := First;
    FBreakRanges[High(FBreakRanges)].Last := Last;
    FBreakRanges[High(FBreakRanges)].Port := Port;
  end;
end;

procedure TSpectrum.SetBreakpoint(Addr: Word; Flags: Byte);
var
  R, A: Integer;
begin
  R := BreakRangeIndex(Addr, False);
  if FIsC64 then
  begin
    // The C64 keeps its breakpoints by address; a range is one breakpoint here, over all its addresses
    if R < 0 then FC64.SetBreakpoint(Addr, Flags)
    else
    begin
      for A := FBreakRanges[R].First to FBreakRanges[R].Last do FC64.SetBreakpoint(A, Flags);
      if Flags = 0 then DeleteBreakRange(R);
    end;
    Exit;
  end;
  if R < 0 then
  begin
    SetOneBreakpoint(Addr, Flags);
    Exit;
  end;
  for A := FBreakRanges[R].First to FBreakRanges[R].Last do SetOneBreakpoint(A, Flags);
  if Flags = 0 then DeleteBreakRange(R);
end;

procedure TSpectrum.SetOneBreakpoint(Addr: Word; Flags: Byte);
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
  if FIsC64 then FC64.ClearBreakpoints;
  FillChar(FBreakFlags, SizeOf(FBreakFlags), 0);
  FMemBreakpoints := 0;
  for I := 0 to High(FBreakConds) do FreeAndNil(FBreakConds[I]);
  FillChar(FPortBreakFlags, SizeOf(FPortBreakFlags), 0);
  FPortBreakpoints := 0;
  for I := 0 to High(FPortBreakConds) do FreeAndNil(FPortBreakConds[I]);
  SetLength(FBreakRanges, 0);
end;

function TSpectrum.GetPortBreakpoint(Port: Word): Byte;
begin
  Result := FPortBreakFlags[Port];
end;

procedure TSpectrum.SetPortBreakpoint(Port: Word; Flags: Byte);
var
  R, A: Integer;
begin
  R := BreakRangeIndex(Port, True);
  if R < 0 then
  begin
    SetOnePortBreakpoint(Port, Flags);
    Exit;
  end;
  for A := FBreakRanges[R].First to FBreakRanges[R].Last do SetOnePortBreakpoint(A, Flags);
  if (Flags and (BP_READ or BP_WRITE)) = 0 then DeleteBreakRange(R);
end;

procedure TSpectrum.SetOnePortBreakpoint(Port: Word; Flags: Byte);
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
  R, A, First, Last: Integer;
begin
  Error := '';
  R := BreakRangeIndex(Port, True);
  if R >= 0 then
  begin
    First := FBreakRanges[R].First;
    Last := FBreakRanges[R].Last;
  end
  else
  begin
    First := Port;
    Last := Port;
  end;
  // Every port of a range has its own copy (with its own hit count)
  for A := First to Last do
  begin
    Cond := nil;
    if Trim(Text) <> '' then
    begin
      Cond := CompileCondition(Text, Error);
      if Cond = nil then Exit(False);
    end;
    if Length(FPortBreakConds) = 0 then SetLength(FPortBreakConds, $10000);
    FPortBreakConds[A].Free;
    FPortBreakConds[A] := Cond;
  end;
  Result := True;
end;

function TSpectrum.BreakHits(Addr: Word): Integer;
begin
  if FIsC64 then Exit(FC64.BreakHits(Addr));
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
  if (FPortBreakpoints = 0) or FSuppressBreaks or FDebugOut then Exit;
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
  R, A, First, Last: Integer;
begin
  if FIsC64 then Exit(FC64.SetCondition(Addr, Text, Error));
  Error := '';
  R := BreakRangeIndex(Addr, False);
  if R >= 0 then
  begin
    First := FBreakRanges[R].First;
    Last := FBreakRanges[R].Last;
  end
  else
  begin
    First := Addr;
    Last := Addr;
  end;
  // Every address of a range has its own copy (with its own hit count)
  for A := First to Last do
  begin
    Cond := nil;
    if Trim(Text) <> '' then
    begin
      Cond := CompileCondition(Text, Error);
      if Cond = nil then Exit(False);
    end;
    if Length(FBreakConds) = 0 then SetLength(FBreakConds, $10000);
    FBreakConds[A].Free;
    FBreakConds[A] := Cond;
  end;
  Result := True;
end;

function TSpectrum.BreakCondition(Addr: Word): string;
begin
  if FIsC64 then Exit(FC64.ConditionOf(Addr));
  if (Length(FBreakConds) > 0) and (FBreakConds[Addr] <> nil) then
    Result := FBreakConds[Addr].Text
  else
    Result := '';
end;

procedure TSpectrum.LogPort(Port: Word; Value: Byte; Write: Boolean);
begin
  if FDebugOut then Exit;
  FPortLog[FPortLogPos].PC := FInstrPC;
  FPortLog[FPortLogPos].Port := Port;
  FPortLog[FPortLogPos].Value := Value;
  FPortLog[FPortLogPos].Write := Write;
  FPortLog[FPortLogPos].Step := FStepCount;
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
  if FIsC64 then
  begin
    FC64.SkipBreakpointOnce;
    Exit;
  end;
  FSkipBreakOnce := True;
  FSkipProbeOnce := FBreakKind in [bkMemory, bkPort];
end;

{ Frame execution }

{ One step of the frame loop: an NMI, an accepted interrupt, or one instruction. }
procedure TSpectrum.ExecuteOne;
begin
  if FIsCPC then
  begin
    ExecuteOneCPC;
    Exit;
  end;
  if FIsMSX then
  begin
    ExecuteOneMSX;
    Exit;
  end;
  if FTrackPrev then
  begin
    FPrevRegs := FCpu.GetRegs;
    FPrevPaging := PagingState;
  end;
  Inc(FStepCount);
  if FNMIRequest then
  begin
    FNMIRequest := False;
    // The Next keeps the return address in NR C2-C3; with the stackless NMI
    // (NR C0 bit 3) only there, and the first RETN returns to it
    if IsNext then
    begin
      if FCpu.Halted then
      begin
        FNextReg[$C2] := Byte(FCpu.PC.W + 1);
        FNextReg[$C3] := Word(FCpu.PC.W + 1) shr 8;
      end
      else
      begin
        FNextReg[$C2] := FCpu.PC.L;
        FNextReg[$C3] := FCpu.PC.H;
      end;
      FNmiStackless := (FNextReg[$C0] and 8) <> 0;
    end;
    FCpu.NMI(IsNext and FNmiStackless);
    Exit;
  end;
  if IntActive and FCpu.IFF1 and FCpu.Interrupt then Exit;
  // The Next: esxDOS calls on the .nex file its program was given
  if (FNexData <> nil) and (FCpu.PC.W = $0008) and NexFileCall then Exit;
  // (the SAM's DOS load trap is in its ROM 1, at the top)
  if (FCpu.PC.W < $4000) or (FIsSAM and (FCpu.PC.W = $E2B6)) then
  begin
    CheckTraps;
    if (FCpu.PC.W = $0008) and (FDivOn or (FModel = smZXUno)) then NoteEsxdosCall;
  end;
  FInstrPC := FCpu.PC.W;
  FSuppressBreaks := FProbeCovered;
  FCpu.Step;
  FSuppressBreaks := False;
  // The Next's DMA sending bytes in burst mode (sampled sound)
  if FDmaActive then DmaRun(MaxInt);
  // The copper, when it has a register to write
  if IsNext and not FCopperStopped and (U(FCpu.T) * 4 >= FCopperDue) then
    NextRenderUpTo(U(FCpu.T), False);
  // NR 02: a reset, once the instruction that asked for it is over
  if FNextResetReq > 0 then
  begin
    Reset(FNextResetReq = 2);
    FNextResetReq := 0;
  end;
end;

procedure TSpectrum.FinishFrame;
begin
  if FIsCPC then
  begin
    FinishFrameCPC;
    Exit;
  end;
  if FIsMSX then
  begin
    FinishFrameMSX;
    Exit;
  end;
  if FUnoAutoLoad >= 0 then ZXUnoAutoLoadStep;
  RenderUpTo(MaxInt);
  if IsNext then
  begin
    // The copper's clock into the next frame
    Dec(FCopperClk, FInfo.FrameT * 4);
    if FCopperClk < 0 then FCopperClk := 0;
    if FCopperDue <> MaxInt then FCopperDue := Max(0, FCopperDue - FInfo.FrameT * 4);
    FCopperRestarted := False;
  end;
  FTape.AdvanceTo(FrameLength);
  GenerateAudio;

  if FRecorder.Active then
  begin
    // The SAM Coupe's 6 MHz in the tape's 3.5 MHz
    if FIsSAM then FRecorder.Idle((FCpuTBase + FrameLength) * 7 div 12)
    else FRecorder.Idle(FCpuTBase + FrameLength);
  end;
  Inc(FCpuTBase, FrameLength);
  Dec(FCpu.T, FrameLength);
  FTape.EndFrame(FrameLength);
  TapeAuto;
  if FPendingSpeed <> FSpeed then
  begin
    // Keep the position within the frame when the clock changes
    FCpu.T := FCpu.T div FSpeed * FPendingSpeed;
    FSpeed := FPendingSpeed;
    UpdateContend;
  end;
  FFDC.Tick;
  FWD.Tick;
  FRenderLine := 0;
  FNextDrawnX := 0;
  FRenderCell := 0;
  Inc(FFrameCount);
  AdvanceAutoKeys;
  if FIsSAM then
  begin
    SAMSyncAutoKeys;
    if (FSamPlayFrame >= 0) and (FFrameCount >= FSamPlayFrame) then
    begin
      FSamPlayFrame := -1;
      if not FTape.Playing then PlayTape;
    end;
    if (FSamSwapDisk <> nil) and (FFrameCount >= FSamSwapFrame) then
    begin
      InsertDiskAt(0, FSamSwapDisk);
      FSamSwapDisk := nil;
    end;
  end;
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
  if FIsC64 then Exit(RunFrameC64);
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
  if FIsC64 then
  begin
    StepInstructionC64;
    Exit;
  end;
  FBreakHit := False;
  FBreakKind := bkNone;
  FSkipBreakOnce := False;
  ExecuteOne;
  if FCpu.T >= FrameLength then FinishFrame;
  // Show the picture up to the current beam position
  RenderUpTo(U(FCpu.T));
end;

{$I SpectrumCPC.inc}
{$I SpectrumSAM.inc}
{$I SpectrumChips.inc}
{$I SpectrumC64.inc}
{$I SpectrumMSX.inc}
{$I NextVideo.inc}
{$I NextDma.inc}
{$I SpectrumNext.inc}
{$I OchentaSnap.inc}

end.
