{ Sam: the hardware of the SAM Coupe that is not a Spectrum's: the ASIC's
  registers (the memory paging LMPR and HMPR, the video page and mode VMPR,
  the border, the colour look-up table, the line interrupt), the interrupts
  seen from the CPU, the keyboard matrix and the picture.

  Written from the SAM Coupe Technical Manual v3.0 (the ports, the paging, the
  four screen modes, the CLUT); the timing the manual leaves out is chosen so
  that the ROM and the software run: a frame is 312 lines of 384 T-states
  (6 MHz), 64 lines of top border, the 192 of the screen, 56 of bottom border;
  in a line 64 T-states of left border, 128 of screen (256 pixels in the
  modes 1, 2 and 4, 512 in the mode 3) and 64 of right border. A line is
  drawn in cells of 4 T-states as the beam goes by, with the registers it has
  then: a change shows from the next cell, in the middle of a line too. }
unit Sam;

{$mode objfpc}{$H+}

interface

const
  SAM_LINE_T = 384;               // T-states in a scanline
  SAM_LINES = 312;                // scanlines in a frame
  SAM_FRAME_T = SAM_LINE_T * SAM_LINES;
  SAM_TOP_LINES = 64;             // lines before the first of the screen
  SAM_SCREEN_LINES = 192;
  SAM_LEFT_T = 64;                // T-states before the screen in a line
  SAM_SCREEN_T = 128;             // T-states of the screen in a line
  SAM_CELLS = 64;                 // 4 T-state cells of a line that are drawn
  SAM_LINE_INT_T = 320;           // where in the line before the LINE interrupt starts: the beam is hidden (the ROM's handler takes about 370 T-states to its colour write, which must land while it is)
  SAM_INT_T = 128;                // an interrupt stays asserted this long
  SAM_PAGES = 32;                 // 16K pages of a 512K machine

  { Sections of the CPU's address space as SectionPage returns them }
  SAM_ROM0 = -1;
  SAM_ROM1 = -2;
  SAM_NO_RAM = -3;                // a page the machine has no memory for

  { The 9 rows of the keyboard matrix, 8 keys each: key = row * 8 + bit. Bits
    0-4 are read at port FE (K1-K5), bits 5-7 at port F9 (K6-K8); row 8 is
    read with the whole high byte of the address set. }
  SAMK_SHIFT = 0;   SAMK_Z = 1;     SAMK_X = 2;     SAMK_C = 3;     SAMK_V = 4;
  SAMK_F1 = 5;      SAMK_F2 = 6;    SAMK_F3 = 7;
  SAMK_A = 8;       SAMK_S = 9;     SAMK_D = 10;    SAMK_F = 11;    SAMK_G = 12;
  SAMK_F4 = 13;     SAMK_F5 = 14;   SAMK_F6 = 15;
  SAMK_Q = 16;      SAMK_W = 17;    SAMK_E = 18;    SAMK_R = 19;    SAMK_T = 20;
  SAMK_F7 = 21;     SAMK_F8 = 22;   SAMK_F9 = 23;
  SAMK_1 = 24;      SAMK_2 = 25;    SAMK_3 = 26;    SAMK_4 = 27;    SAMK_5 = 28;
  SAMK_ESC = 29;    SAMK_TAB = 30;  SAMK_CAPS = 31;
  SAMK_0 = 32;      SAMK_9 = 33;    SAMK_8 = 34;    SAMK_7 = 35;    SAMK_6 = 36;
  SAMK_MINUS = 37;  SAMK_PLUS = 38; SAMK_DELETE = 39;
  SAMK_P = 40;      SAMK_O = 41;    SAMK_I = 42;    SAMK_U = 43;    SAMK_Y = 44;
  SAMK_EQUALS = 45; SAMK_QUOTE = 46; SAMK_F0 = 47;
  SAMK_RETURN = 48; SAMK_L = 49;    SAMK_K = 50;    SAMK_J = 51;    SAMK_H = 52;
  SAMK_SEMICOLON = 53; SAMK_COLON = 54; SAMK_EDIT = 55;
  SAMK_SPACE = 56;  SAMK_SYMBOL = 57; SAMK_M = 58;  SAMK_N = 59;    SAMK_B = 60;
  SAMK_COMMA = 61;  SAMK_PERIOD = 62; SAMK_INV = 63;
  SAMK_CTRL = 64;   SAMK_UP = 65;   SAMK_DOWN = 66; SAMK_LEFT = 67;  SAMK_RIGHT = 68;
  SAMK_COUNT = 72;

{ The key (and the SHIFT or SYMBOL, -1 if none) that makes a character on the SAM's keyboard, as
  its ROM's key table has it: for the characters that need no Shift on a PC keyboard of any layout
  (the keyboard layout gives the character; this says which SAM keys produce it) }
function SamKeysForChar(Ch: Char; out Key, Modifier: Integer): Boolean;

type
  TSam = class
  private
    FRam: PByte;                       // the RAM, in pages of 16K, from page 0
    FRamPages: Integer;
    FMouseDX, FMouseDY: Integer;       // movement not yet read, in SAM mouse counts (Y up)
    FMouseSeq: Integer;                // the next byte of the mouse's sequence
    FMouseLastT: Int64;
    FMouseBuf: array[0..8] of Byte;
    FMouseSentX, FMouseSentY: Integer;
    FRgb: array[0..127] of LongWord;   // the 128 colours of the CLUT
    function PixelColour(Index: Integer): LongWord; inline;
    function VideoByte(Offset: Integer): Byte; inline;
  public
    LMPR, HMPR, VMPR: Byte;
    Border: Byte;                      // port FE as it was written
    LineInt: Byte;                     // port F9: the line that interrupts (192-255: none)
    Clut: array[0..15] of Byte;
    Keys: array[0..8] of Byte;         // bit set: the key is down
    AutoKeys: array[0..8] of Byte;     // the same, for the keys typed by the emulator
    FlashOn: Boolean;
    { The mouse (read through the keyboard port with its high byte $FF) and the clock (port $EF) }
    MouseButtons: Byte;                // bit n-1 set: button n is down
    ClockCtl: array[13..15] of Byte;   // the clock's control registers D, E, F
    procedure MouseMoved(DX, DY: Integer);
    function MouseRead(AbsT: Int64): Byte;
    function ClockRead(Reg: Integer): Byte;
    procedure ClockWrite(Reg: Integer; Value: Byte);
    constructor Create;
    { RAM: the machine's memory, Pages of 16K from Base }
    procedure SetRam(Base: PByte; Pages: Integer);
    procedure Reset;
    { What is paged in a section (0-3 of 16K) of the address space: a RAM
      page (0-31), SAM_ROM0, SAM_ROM1 or SAM_NO_RAM; ReadOnly if writes are
      ignored there }
    function SectionPage(Section: Integer; out ReadOnly: Boolean): Integer;
    function ScreenMode: Integer;      // 1 to 4
    function ScreenOff: Boolean;       // port FE bit 7 (modes 3 and 4)
    function BorderColour: Integer;    // CLUT entry of the border
    procedure SetClut(Index, Value: Byte);
    { Port FE (K1-K5, active low) and F9's upper bits (K6-K8) for the rows
      the high byte of the address selects }
    function ReadKeyboard(HighByte: Byte; out High3: Byte): Byte;
    function KeyDownCount: Integer;
    { The interrupt lines at a time of the frame (T-states): the bits 0-4 of
      the status port, 0 where one is requested (LINE, MOUSE, MIDIIN, FRAME,
      MIDIOUT) }
    function InterruptStatus(T: Integer): Byte;
    { T-states the CPU waits for the ASIC when it reads or writes RAM (or a port) at frame time T:
      the access is held to a 4 T-state grid, to an 8 T-state one while the ASIC is fetching the
      picture (all of mode 1's left half-line too) }
    function WaitStates(T: Integer): Integer;
    function InterruptActive(T: Integer): Boolean;
    { T-state of the frame by which the picture's row (0 to height - 1 of
      the frame buffer) has been drawn, and its drawing; Row's width is
      Width pixels, the border Border pixels on each side of the screen }
    { The frame's T-state at which a frame buffer row starts (its first cell) }
    function RowStartT(Row, BorderTop: Integer): Integer;
    procedure DrawCells(Row, BorderTop, BorderLeft, C0, C1: Integer; Dest: PLongWord);
  end;

implementation

uses
  SysUtils;

function SamKeysForChar(Ch: Char; out Key, Modifier: Integer): Boolean;
const
  LETTERS: array['A'..'Z'] of Integer = (
    SAMK_A, SAMK_B, SAMK_C, SAMK_D, SAMK_E, SAMK_F, SAMK_G, SAMK_H, SAMK_I, SAMK_J, SAMK_K, SAMK_L,
    SAMK_M, SAMK_N, SAMK_O, SAMK_P, SAMK_Q, SAMK_R, SAMK_S, SAMK_T, SAMK_U, SAMK_V, SAMK_W, SAMK_X,
    SAMK_Y, SAMK_Z);
  DIGITS: array['0'..'9'] of Integer = (
    SAMK_0, SAMK_1, SAMK_2, SAMK_3, SAMK_4, SAMK_5, SAMK_6, SAMK_7, SAMK_8, SAMK_9);
  // Keys with their own character, plain
  PLAIN = '"=+-;:,. ';
  PLAIN_KEYS: array[1..Length(PLAIN)] of Integer = (
    SAMK_QUOTE, SAMK_EQUALS, SAMK_PLUS, SAMK_MINUS, SAMK_SEMICOLON, SAMK_COLON, SAMK_COMMA,
    SAMK_PERIOD, SAMK_SPACE);
  // With Shift: the digits' row, the signs on the sign keys and the backslash (INV)
  SHIFTED = '!@#$%&''()~*_/\';
  SHIFTED_KEYS: array[1..Length(SHIFTED)] of Integer = (
    SAMK_1, SAMK_2, SAMK_3, SAMK_4, SAMK_5, SAMK_6, SAMK_7, SAMK_8, SAMK_9, SAMK_0,
    SAMK_PLUS, SAMK_EQUALS, SAMK_MINUS, SAMK_INV);
  // With Symbol: brackets, braces, comparisons, the bar, the accent and the question mark
  SYMBOLS = '?[]{}<>|`^';
  SYMBOL_KEYS: array[1..Length(SYMBOLS)] of Integer = (
    SAMK_Z, SAMK_R, SAMK_T, SAMK_F, SAMK_G, SAMK_COMMA, SAMK_PERIOD, SAMK_9, SAMK_L, SAMK_H);
var
  P: Integer;
begin
  Result := True;
  Modifier := -1;
  if Ch in ['a'..'z'] then Key := LETTERS[UpCase(Ch)]
  else if Ch in ['A'..'Z'] then
  begin
    Key := LETTERS[Ch];
    Modifier := SAMK_SHIFT;
  end
  else if Ch in ['0'..'9'] then Key := DIGITS[Ch]
  else
  begin
    P := Pos(Ch, PLAIN);
    if P > 0 then Key := PLAIN_KEYS[P]
    else
    begin
      P := Pos(Ch, SHIFTED);
      if P > 0 then
      begin
        Key := SHIFTED_KEYS[P];
        Modifier := SAMK_SHIFT;
      end
      else
      begin
        P := Pos(Ch, SYMBOLS);
        if P > 0 then
        begin
          Key := SYMBOL_KEYS[P];
          Modifier := SAMK_SYMBOL;
        end
        else
          Result := False;
      end;
    end;
  end;
end;

{ The CLUT's 7 bits: 0 blue, 1 red, 2 green (low bits), 3 bright, 4 blue, 5
  red, 6 green (high bits); each colour has 8 levels: its two bits and the
  bright bit }
constructor TSam.Create;
var
  I, R, G, B: Integer;

  function Level(Hi, Lo, Bright: Integer): Integer;
  begin
    Result := (Hi * 4 + Lo * 2 + Bright) * 255 div 7;
  end;

begin
  inherited Create;
  for I := 0 to 127 do
  begin
    B := Level((I shr 4) and 1, I and 1, (I shr 3) and 1);
    R := Level((I shr 5) and 1, (I shr 1) and 1, (I shr 3) and 1);
    G := Level((I shr 6) and 1, (I shr 2) and 1, (I shr 3) and 1);
    FRgb[I] := (LongWord(R) shl 16) or (LongWord(G) shl 8) or LongWord(B);
  end;
  FRamPages := SAM_PAGES;
  Reset;
end;

procedure TSam.SetRam(Base: PByte; Pages: Integer);
begin
  FRam := Base;
  FRamPages := Pages;
end;

procedure TSam.Reset;
const
  { The ROM loads these at power on }
  DEFAULT_CLUT: array[0..15] of Byte = (0, 16, 32, 48, 64, 80, 96, 120, 0, 17, 34, 51, 68, 85, 102, 127);
var
  I: Integer;
begin
  LMPR := 0;
  HMPR := 0;
  VMPR := 0;
  Border := 0;
  LineInt := 255;
  for I := 0 to 15 do Clut[I] := DEFAULT_CLUT[I];
  FillChar(Keys, SizeOf(Keys), 0);
  FillChar(AutoKeys, SizeOf(AutoKeys), 0);
  FMouseDX := 0;
  FMouseDY := 0;
  FMouseSeq := 0;
  FMouseBuf[0] := 15;
  FMouseBuf[1] := 15;
  MouseButtons := 0;
  ClockCtl[13] := 0;
  ClockCtl[14] := 0;
  ClockCtl[15] := 4;                   // 24 hour mode
end;

{ A mouse that waits this long between reads starts its sequence again }
const
  SAM_MOUSE_RESET_T = 6000;

{ The host's mouse moved: DX to the right, DY down, in SAM mouse counts }
procedure TSam.MouseMoved(DX, DY: Integer);
begin
  Inc(FMouseDX, DX);
  Dec(FMouseDY, DY);                   // the SAM counts upwards
  if FMouseDX > 127 then FMouseDX := 127 else if FMouseDX < -127 then FMouseDX := -127;
  if FMouseDY > 127 then FMouseDY := 127 else if FMouseDY < -127 then FMouseDY := -127;
end;

{ One read of the mouse: a sequence of nibbles (the upper four bits are 1): two header bytes, the
  buttons (a pressed one reads 0), X and Y as 12 bit two's complement numbers, hundreds nibble
  first. The movement is taken at the third read and what was sent is not counted again. }
function TSam.MouseRead(AbsT: Int64): Byte;
var
  I: Integer;
begin
  if AbsT - FMouseLastT > SAM_MOUSE_RESET_T then FMouseSeq := 0;
  FMouseLastT := AbsT;
  if FMouseSeq = 2 then
  begin
    FMouseBuf[0] := 15;
    FMouseBuf[1] := 15;
    FMouseBuf[2] := (not MouseButtons) and 15;
    FMouseSentX := FMouseDX;
    FMouseSentY := FMouseDY;
    for I := 0 to 2 do
    begin
      FMouseBuf[3 + I] := (FMouseSentX shr (8 - I * 4)) and 15;
      FMouseBuf[6 + I] := (FMouseSentY shr (8 - I * 4)) and 15;
    end;
  end;
  Result := $F0;
  if FMouseSeq <= 8 then Result := $F0 or (FMouseBuf[FMouseSeq] and 15) else Result := $FF;
  Inc(FMouseSeq);
  if FMouseSeq > 8 then
  begin
    Dec(FMouseDX, FMouseSentX);
    Dec(FMouseDY, FMouseSentY);
    FMouseSeq := 1;                    // again, without the first header byte
  end;
end;

{ The clock of the SAMBUS interface (an OKI MSM6242: the time in digits of 4 bits, ones then
  tens: seconds, minutes, hours, day, month, year; then the day of the week and three control
  registers) follows the PC's clock; the high byte of the port address says the register }
function TSam.ClockRead(Reg: Integer): Byte;
var
  Now: TDateTime;
  Y, Mo, D, H, Mi, S, MS: Word;
  V: Integer;
begin
  Reg := Reg and 15;
  Result := $F0;
  if Reg >= 13 then
  begin
    Result := $F0 or (ClockCtl[Reg] and 15);
    Exit;
  end;
  Now := SysUtils.Now;
  DecodeDate(Now, Y, Mo, D);
  DecodeTime(Now, H, Mi, S, MS);
  case Reg of
    0, 1: V := S;
    2, 3: V := Mi;
    4, 5:
      if (ClockCtl[15] and 4) <> 0 then V := H
      else
      begin
        // 12 hour mode: the PM bit is bit 2 of the tens
        V := H mod 12;
        if V = 0 then V := 12;
        if H >= 12 then Inc(V, 40);
      end;
    6, 7: V := D;
    8, 9: V := Mo;
    10, 11: V := Y mod 100;
    12: V := DayOfWeek(Now) - 1;
  else
    V := 0;
  end;
  if Reg = 12 then
    Result := $F0 or V
  else if Odd(Reg) then
    Result := $F0 or ((V div 10) and 15)
  else
    Result := $F0 or (V mod 10);
end;

procedure TSam.ClockWrite(Reg: Integer; Value: Byte);
begin
  Reg := Reg and 15;
  // The time itself follows the PC's clock; only the control registers are kept
  if Reg >= 13 then ClockCtl[Reg] := Value and 15;
end;

function TSam.SectionPage(Section: Integer; out ReadOnly: Boolean): Integer;
var
  Page: Integer;
begin
  ReadOnly := False;
  case Section of
    0:
      if (LMPR and $20) = 0 then
      begin
        ReadOnly := True;
        Exit(SAM_ROM0);
      end
      else
      begin
        ReadOnly := (LMPR and $80) <> 0;
        Page := LMPR and $1F;
      end;
    1: Page := ((LMPR and $1F) + 1) and $1F;
    2: Page := HMPR and $1F;
  else
    if (LMPR and $40) <> 0 then
    begin
      ReadOnly := True;
      Exit(SAM_ROM1);
    end;
    Page := ((HMPR and $1F) + 1) and $1F;
  end;
  if Page >= FRamPages then
  begin
    ReadOnly := True;
    Exit(SAM_NO_RAM);
  end;
  Result := Page;
end;

function TSam.ScreenMode: Integer;
begin
  Result := ((VMPR shr 5) and 3) + 1;
end;

function TSam.ScreenOff: Boolean;
begin
  Result := (Border and $80) <> 0;
end;

function TSam.BorderColour: Integer;
begin
  Result := (Border and 7) or ((Border and $20) shr 2);
end;

procedure TSam.SetClut(Index, Value: Byte);
begin
  Clut[Index and 15] := Value and $7F;
end;

function TSam.ReadKeyboard(HighByte: Byte; out High3: Byte): Byte;
var
  Row: Integer;
  Down: Byte;
begin
  Down := 0;
  if HighByte = $FF then
    Down := Keys[8] or AutoKeys[8]
  else
    for Row := 0 to 7 do
      if (HighByte and (1 shl Row)) = 0 then Down := Down or Keys[Row] or AutoKeys[Row];
  Result := not Down and $1F;
  High3 := not Down and $E0;
end;

function TSam.KeyDownCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to 8 do if (Keys[I] or AutoKeys[I]) <> 0 then Inc(Result);
end;

function TSam.WaitStates(T: Integer): Integer;
var
  Line, X, Mask: Integer;
begin
  Line := T div SAM_LINE_T;
  X := T - Line * SAM_LINE_T;
  Mask := 3;
  if (Line >= 64) and (Line < 256) then
    if ScreenMode = 1 then
    begin
      if ((X >= 64) and (X < 192)) or ((X and $40) = 0) then Mask := 7;
    end
    else if not ScreenOff and (X >= 64) and (X < 192) then Mask := 7;
  Result := Mask - ((T + 2) and Mask);
end;

function TSam.InterruptStatus(T: Integer): Byte;
var
  LineT: Integer;
begin
  Result := $1F;
  // FRAME: the frame scan is over, at the start of the next
  if T < SAM_INT_T then Result := Result and not $08;
  // LINE: as the line before the one in port F9 ends (its handler changes the colours while the beam is hidden)
  if LineInt < SAM_SCREEN_LINES then
  begin
    LineT := (SAM_TOP_LINES + LineInt - 1) * SAM_LINE_T + SAM_LINE_INT_T;
    if (T >= LineT) and (T < LineT + SAM_INT_T) then Result := Result and not $01;
  end;
end;

function TSam.InterruptActive(T: Integer): Boolean;
begin
  Result := InterruptStatus(T) <> $1F;
end;

function TSam.RowStartT(Row, BorderTop: Integer): Integer;
begin
  Result := (Row + SAM_TOP_LINES - BorderTop) * SAM_LINE_T;
end;

function TSam.PixelColour(Index: Integer): LongWord;
begin
  Result := FRgb[Clut[Index and 15] and $7F];
end;

{ A byte of the screen: Offset from the start of the video page; the 24K of
  the modes 3 and 4 go on into the next page of the same pair }
function TSam.VideoByte(Offset: Integer): Byte;
var
  Page: Integer;
begin
  Page := VMPR and $1F;
  if Offset >= $4000 then
  begin
    Page := Page xor 1;
    Offset := Offset and $3FFF;
  end;
  if (FRam = nil) or (Page >= FRamPages) then Exit($FF);
  Result := FRam[Page * $4000 + Offset];
end;

{ The picture's cells, each 4 T-states of the line: 16 of left border (6 pixels each), 32 of screen
  (16 pixels, a byte of the SAM's 8 low-resolution pixels or 4 of the 512 ones) and 16 of right
  border. Cells C0 to C1-1 of the row are drawn with the registers as they are now, which lets a
  program change the border, the CLUT or the mode in the middle of a line. }
procedure TSam.DrawCells(Row, BorderTop, BorderLeft, C0, C1: Integer; Dest: PLongWord);
var
  Y, Mode, C, Col, Off, Attr, B, Bit, Ink, Paper, Sel, Px, N, K: Integer;
  Border32, Pix, Pix2: LongWord;
  P: PLongWord;
  BorderRow: Boolean;
begin
  Border32 := PixelColour(BorderColour);
  Y := Row - BorderTop;
  Mode := ScreenMode;
  BorderRow := (Y < 0) or (Y >= SAM_SCREEN_LINES) or (ScreenOff and (Mode >= 3));
  for C := C0 to C1 - 1 do
  begin
    if C < 16 then
    begin
      Px := C * 6;
      N := 6;
    end
    else if C < 48 then
    begin
      Px := BorderLeft * 2 + (C - 16) * 16;
      N := 16;
    end
    else
    begin
      Px := BorderLeft * 2 + 512 + (C - 48) * 6;
      N := 6;
    end;
    P := Dest + Px;
    if BorderRow or (C < 16) or (C >= 48) then
    begin
      for K := 1 to N do
      begin
        P^ := Border32;
        Inc(P);
      end;
      Continue;
    end;
    Col := C - 16;
    case Mode of
      1, 2:
        begin
          if Mode = 1 then
            Off := ((Y and $C0) shl 5) or ((Y and 7) shl 8) or ((Y and $38) shl 2)
          else
            Off := Y * 32;
          B := VideoByte(Off + Col);
          if Mode = 1 then Attr := VideoByte($1800 + (Y shr 3) * 32 + Col)
          else Attr := VideoByte($2000 + Y * 32 + Col);
          Ink := (Attr and 7) or ((Attr shr 3) and 8);
          Paper := ((Attr shr 3) and 7) or ((Attr shr 3) and 8);
          if FlashOn and ((Attr and $80) <> 0) then
          begin
            Sel := Ink;
            Ink := Paper;
            Paper := Sel;
          end;
          for Bit := 0 to 7 do
          begin
            if (B and ($80 shr Bit)) <> 0 then Pix := PixelColour(Ink) else Pix := PixelColour(Paper);
            P^ := Pix;
            Inc(P);
            P^ := Pix;
            Inc(P);
          end;
        end;
      3:
        begin
          // 512 pixels of 2 bits: the 4 colours are the group of the CLUT that HMPR bits 5 and 6 choose
          Sel := ((HMPR shr 5) and 3) shl 2;
          Off := Y * 128 + Col * 4;
          for K := 0 to 3 do
          begin
            B := VideoByte(Off + K);
            for Bit := 0 to 3 do
            begin
              P^ := PixelColour(Sel + ((B shr (6 - Bit * 2)) and 3));
              Inc(P);
            end;
          end;
        end;
    else
      // Mode 4: 256 pixels of 4 bits, the most significant nibble first
      Off := Y * 128 + Col * 4;
      for K := 0 to 3 do
      begin
        B := VideoByte(Off + K);
        Pix := PixelColour(B shr 4);
        Pix2 := PixelColour(B and 15);
        P^ := Pix;
        Inc(P);
        P^ := Pix;
        Inc(P);
        P^ := Pix2;
        Inc(P);
        P^ := Pix2;
        Inc(P);
      end;
    end;
  end;
end;

end.
