{ Currah: the Currah µSpeech (MicroSpeech) interface for the 16K/48K and its
  speech chip, a General Instrument SP0256-AL2.

  The interface (as zxsp, by Günter Woigk, describes it): any access to
  address 0038 (read, write, opcode fetch, IN or OUT) toggles its 2K ROM,
  which then sits at 0000-07FF and again at 0800-0FFF. Writing 1000 sends
  an allophone (the low 6 bits) to the chip; reading 1000 while the ROM is
  in gives the chip's state in bit 0 (1: busy, it can't take another one).
  Writing 3000 or 3001 sets the intonation: the chip's clock is 3.05 MHz,
  or about 7% faster after 3001. The interface's ROM hooks into the
  interrupt at 0038 (its byte there is PUSH AF, the same as the Spectrum's).

  The SP0256 is a port of MAME's sp0256.cpp (BSD-3-Clause, Joseph Zbiciak
  and Tim Lindner): a microsequencer runs the allophone programs in the
  chip's 2K mask ROM (at 1000 in its address space, mask ROM © Microchip)
  and feeds a 12-pole LPC filter, one sample every 312 clocks (about 9.8
  kHz). The SPB640 FIFO isn't emulated (the Currah doesn't have it).

  The SP0256 part, as MAME's licence asks:

  Copyright (c) Joseph Zbiciak, Tim Lindner. All rights reserved.
  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are met:
  1. Redistributions of source code must retain the above copyright notice,
     this list of conditions and the following disclaimer.
  2. Redistributions in binary form must reproduce the above copyright notice,
     this list of conditions and the following disclaimer in the documentation
     and/or other materials provided with the distribution.
  3. Neither the name of the copyright holder nor the names of its
     contributors may be used to endorse or promote products derived from
     this software without specific prior written permission.
  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
  POSSIBILITY OF SUCH DAMAGE. }
unit Currah;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  SysUtils, Classes, Math;

const
  CURRAH_ROM_SIZE = 2048;
  SP0256_ROM_SIZE = 2048;
  { Chip clocks: normal, and about 7% faster for the raised intonation }
  SP_CLOCK_LOW = 3050000;
  SP_CLOCK_HIGH = 3260000;

type
  { The SP0256's 12-pole filter and its excitation }
  TLpc12 = record
    Rpt, Cnt: Integer;       // repeat counter; period counter
    Per: Integer;            // period (0: noise)
    Rng: Integer;            // noise generator
    Amp: Integer;
    FCoef, BCoef: array[0..5] of SmallInt;
    ZData: array[0..5, 0..1] of SmallInt;
    R: array[0..15] of Byte; // the parameter registers
    Interp: Boolean;
  end;

  TSP0256 = class
  private
    FRom: array of Byte;     // 64K address space, the mask ROM at 1000
    FFilt: TLpc12;
    FSilent: Boolean;
    FLrq: Boolean;           // True: ready for another allophone
    FAld: Integer;           // allophone address waiting to be started
    FPc, FStack, FPage: LongWord;   // bit addresses
    FHalted: Boolean;
    FMode: Integer;
    function GetB(Len: Integer): LongWord;
    procedure Micro;
    procedure RegDec;
    function FilterSample(out Sample: SmallInt): Boolean;
  public
    constructor Create;
    procedure LoadRom(const Data: array of Byte);
    procedure Reset;
    { Start an allophone (dropped while the chip isn't ready) }
    procedure WriteAllophone(Value: Byte);
    { The next output sample, -32768..32767 }
    function NextSample: SmallInt;
    property Ready: Boolean read FLrq;
  end;

  { The interface: its ROM paging and the chip, kept in step with the
    emulated time (T-states from the start of the frame) }
  TCurrah = class
  private
    FRom: array[0..CURRAH_ROM_SIZE - 1] of Byte;
    FChip: TSP0256;
    FPaged: Boolean;
    FClock: Integer;
    FChipT: Double;          // time of the chip's next sample
    FClockHz: Integer;       // the Spectrum's clock
    FOut: array of SmallInt; // the chip's samples this frame
    FOutT: array of Double;  // and their times
    FOutCount: Integer;
    FLast: SmallInt;         // the sample being output
    FFilter: Single;         // smoothing to the sound card's rate
    FOutPos: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    { The interface's 2K ROM and the SP0256-AL2's 2K mask ROM; raise if a
      file can't be read }
    procedure LoadRoms(const CurrahFile, ChipFile: string);
    procedure Reset;
    { Run the chip up to T (T-states into the frame) }
    procedure Sync(T: Integer);
    { The level at T-state T of the frame (after Sync to the frame's end),
      -1..1; call with increasing T }
    function Level(T: Double): Single;
    { The frame ended after FrameT T-states }
    procedure EndFrame(FrameT: Integer);
    { An access to address 0038 }
    procedure Toggle;
    function ReadRom(Addr: Word): Byte;
    { Writes to 1000 (allophone), 3000 and 3001 (intonation) at T }
    procedure Write(Addr: Word; Value: Byte; T: Integer);
    { Reading 1000 with the ROM paged in: bit 0 set while busy }
    function ReadStatus(T: Integer): Byte;
    property Paged: Boolean read FPaged write FPaged;
    property ClockHz: Integer read FClockHz write FClockHz;
  end;

implementation

const
  CLOCK_DIVIDER = 6 * 4 * 13;
  PER_PAUSE = 64;
  PER_NOISE = 64;

  AM = 0; PR = 1; B0 = 2; F0 = 3; B1 = 4; F1 = 5; B2 = 6; F2 = 7;
  B3 = 8; F3 = 9; B4 = 10; F4 = 11; B5 = 12; F5 = 13; IA = 14; IP = 15;

  { Coefficient quantization table (from the SP0250 data sheet) }
  QTBL: array[0..127] of SmallInt = (
    0, 9, 17, 25, 33, 41, 49, 57, 65, 73, 81, 89, 97, 105, 113, 121,
    129, 137, 145, 153, 161, 169, 177, 185, 193, 201, 209, 217, 225, 233, 241, 249,
    257, 265, 273, 281, 289, 297, 301, 305, 309, 313, 317, 321, 325, 329, 333, 337,
    341, 345, 349, 353, 357, 361, 365, 369, 373, 377, 381, 385, 389, 393, 397, 401,
    405, 409, 413, 417, 421, 425, 427, 429, 431, 433, 435, 437, 439, 441, 443, 445,
    447, 449, 451, 453, 455, 457, 459, 461, 463, 465, 467, 469, 471, 473, 475, 477,
    479, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495,
    496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511);

{ A control word of the data format table: field length, left shift,
  parameter, delta update, field replace, clear B5/F5, clear all }
function CR(L, S, P, D, F, C5, CA: Integer): Word;
begin
  Result := (L and 15) or ((S and 15) shl 4) or ((P and 15) shl 8) or ((D and 1) shl 12) or
    ((F and 1) shl 13) or ((C5 and 1) shl 14) or ((CA and 1) shl 15);
end;

const
  CR_DELTA = $1000;
  CR_FIELD = $2000;
  CR_CLR5 = $4000;
  CR_CLRA = $8000;

var
  DataFmt: array[0..176] of Word;

  { First and last data format entries for (opcode shl 3) or (mode and 6) }
  DF_IDX: array[0..127] of SmallInt = (
    { 0000 } -1, -1, -1, -1, -1, -1, -1, -1,
    { 1000 } -1, -1, -1, -1, -1, -1, -1, -1,
    { 0100 } 17, 22, 17, 24, 25, 30, 25, 32,
    { 1100 } 83, 94, 129, 142, 97, 108, 145, 158,
    { 0010 } 83, 96, 129, 144, 97, 110, 145, 160,
    { 1010 } 73, 77, 74, 77, 78, 82, 79, 82,
    { 0110 } 33, 36, 34, 37, 38, 41, 39, 42,
    { 1110 } 127, 128, 127, 128, 127, 128, 127, 128,
    { 0001 } 1, 14, 1, 16, 1, 14, 1, 16,
    { 1001 } 45, 56, 45, 58, 59, 70, 59, 72,
    { 0101 } 161, 166, 162, 166, 169, 174, 170, 174,
    { 1101 } 111, 116, 111, 118, 119, 124, 119, 126,
    { 0011 } 161, 168, 162, 168, 169, 176, 170, 176,
    { 1011 } -1, -1, -1, -1, -1, -1, -1, -1,
    { 0111 } -1, -1, -1, -1, -1, -1, -1, -1,
    { 1111 } 0, 0, 0, 0, 0, 0, 0, 0);

procedure InitDataFmt;
var
  N: Integer;

  procedure Add(L, S, P, D, F, C5, CA: Integer);
  begin
    DataFmt[N] := CR(L, S, P, D, F, C5, CA);
    Inc(N);
  end;

begin
  N := 0;
  // 0: PAUSE
  Add(0, 0, 0, 0, 0, 0, 1);
  // 1-16: LOADALL
  Add(8, 0, AM, 0, 0, 0, 1); Add(8, 0, PR, 0, 0, 0, 0);
  Add(8, 0, B0, 0, 0, 0, 0); Add(8, 0, F0, 0, 0, 0, 0);
  Add(8, 0, B1, 0, 0, 0, 0); Add(8, 0, F1, 0, 0, 0, 0);
  Add(8, 0, B2, 0, 0, 0, 0); Add(8, 0, F2, 0, 0, 0, 0);
  Add(8, 0, B3, 0, 0, 0, 0); Add(8, 0, F3, 0, 0, 0, 0);
  Add(8, 0, B4, 0, 0, 0, 0); Add(8, 0, F4, 0, 0, 0, 0);
  Add(8, 0, B5, 0, 0, 0, 0); Add(8, 0, F5, 0, 0, 0, 0);
  Add(8, 0, IA, 0, 0, 0, 0); Add(8, 0, IP, 0, 0, 0, 0);
  // 17-32: LOAD_4
  Add(6, 2, AM, 0, 0, 0, 1); Add(8, 0, PR, 0, 0, 0, 0);
  Add(4, 3, B3, 0, 0, 0, 0); Add(6, 2, F3, 0, 0, 0, 0);
  Add(7, 1, B4, 0, 0, 0, 0); Add(6, 2, F4, 0, 0, 0, 0);
  Add(8, 0, B5, 0, 0, 0, 0); Add(8, 0, F5, 0, 0, 0, 0);
  Add(6, 2, AM, 0, 0, 0, 1); Add(8, 0, PR, 0, 0, 0, 0);
  Add(6, 1, B3, 0, 0, 0, 0); Add(7, 1, F3, 0, 0, 0, 0);
  Add(8, 0, B4, 0, 0, 0, 0); Add(8, 0, F4, 0, 0, 0, 0);
  Add(8, 0, B5, 0, 0, 0, 0); Add(8, 0, F5, 0, 0, 0, 0);
  // 33-42: SETMSB_6
  Add(0, 0, 0, 0, 0, 1, 0);
  Add(6, 2, AM, 0, 0, 0, 0); Add(6, 2, F3, 0, 1, 0, 0); Add(6, 2, F4, 0, 1, 0, 0);
  Add(8, 0, F5, 0, 1, 0, 0);
  Add(0, 0, 0, 0, 0, 1, 0);
  Add(6, 2, AM, 0, 0, 0, 0); Add(7, 1, F3, 0, 1, 0, 0); Add(8, 0, F4, 0, 1, 0, 0);
  Add(8, 0, F5, 0, 1, 0, 0);
  // 43-44: unused
  Add(0, 0, 0, 0, 0, 0, 0); Add(0, 0, 0, 0, 0, 0, 0);
  // 45-72: DELTA_9
  Add(4, 2, AM, 1, 0, 0, 0); Add(5, 0, PR, 1, 0, 0, 0);
  Add(3, 4, B0, 1, 0, 0, 0); Add(3, 3, F0, 1, 0, 0, 0);
  Add(3, 4, B1, 1, 0, 0, 0); Add(3, 3, F1, 1, 0, 0, 0);
  Add(3, 4, B2, 1, 0, 0, 0); Add(3, 3, F2, 1, 0, 0, 0);
  Add(3, 3, B3, 1, 0, 0, 0); Add(4, 2, F3, 1, 0, 0, 0);
  Add(4, 1, B4, 1, 0, 0, 0); Add(4, 2, F4, 1, 0, 0, 0);
  Add(5, 0, B5, 1, 0, 0, 0); Add(5, 0, F5, 1, 0, 0, 0);
  Add(4, 2, AM, 1, 0, 0, 0); Add(5, 0, PR, 1, 0, 0, 0);
  Add(4, 1, B0, 1, 0, 0, 0); Add(4, 2, F0, 1, 0, 0, 0);
  Add(4, 1, B1, 1, 0, 0, 0); Add(4, 2, F1, 1, 0, 0, 0);
  Add(4, 1, B2, 1, 0, 0, 0); Add(4, 2, F2, 1, 0, 0, 0);
  Add(4, 1, B3, 1, 0, 0, 0); Add(5, 1, F3, 1, 0, 0, 0);
  Add(5, 0, B4, 1, 0, 0, 0); Add(5, 0, F4, 1, 0, 0, 0);
  Add(5, 0, B5, 1, 0, 0, 0); Add(5, 0, F5, 1, 0, 0, 0);
  // 73-82: SETMSB_A
  Add(0, 0, 0, 0, 0, 1, 0);
  Add(6, 2, AM, 0, 0, 0, 0); Add(5, 3, F0, 0, 1, 0, 0);
  Add(5, 3, F1, 0, 1, 0, 0); Add(5, 3, F2, 0, 1, 0, 0);
  Add(0, 0, 0, 0, 0, 1, 0);
  Add(6, 2, AM, 0, 0, 0, 0); Add(6, 2, F0, 0, 1, 0, 0);
  Add(6, 2, F1, 0, 1, 0, 0); Add(6, 2, F2, 0, 1, 0, 0);
  // 83-110: LOAD_2 / LOAD_C, modes 00 and 10
  Add(6, 2, AM, 0, 0, 0, 1); Add(8, 0, PR, 0, 0, 0, 0);
  Add(3, 4, B0, 0, 0, 0, 0); Add(5, 3, F0, 0, 0, 0, 0);
  Add(3, 4, B1, 0, 0, 0, 0); Add(5, 3, F1, 0, 0, 0, 0);
  Add(3, 4, B2, 0, 0, 0, 0); Add(5, 3, F2, 0, 0, 0, 0);
  Add(4, 3, B3, 0, 0, 0, 0); Add(6, 2, F3, 0, 0, 0, 0);
  Add(7, 1, B4, 0, 0, 0, 0); Add(6, 2, F4, 0, 0, 0, 0);
  Add(5, 0, IA, 0, 0, 0, 0); Add(5, 0, IP, 0, 0, 0, 0);
  Add(6, 2, AM, 0, 0, 0, 1); Add(8, 0, PR, 0, 0, 0, 0);
  Add(6, 1, B0, 0, 0, 0, 0); Add(6, 2, F0, 0, 0, 0, 0);
  Add(6, 1, B1, 0, 0, 0, 0); Add(6, 2, F1, 0, 0, 0, 0);
  Add(6, 1, B2, 0, 0, 0, 0); Add(6, 2, F2, 0, 0, 0, 0);
  Add(6, 1, B3, 0, 0, 0, 0); Add(7, 1, F3, 0, 0, 0, 0);
  Add(8, 0, B4, 0, 0, 0, 0); Add(8, 0, F4, 0, 0, 0, 0);
  Add(5, 0, IA, 0, 0, 0, 0); Add(5, 0, IP, 0, 0, 0, 0);
  // 111-126: DELTA_D
  Add(4, 2, AM, 1, 0, 0, 0); Add(5, 0, PR, 1, 0, 0, 0);
  Add(3, 3, B3, 1, 0, 0, 0); Add(4, 2, F3, 1, 0, 0, 0);
  Add(4, 1, B4, 1, 0, 0, 0); Add(4, 2, F4, 1, 0, 0, 0);
  Add(5, 0, B5, 1, 0, 0, 0); Add(5, 0, F5, 1, 0, 0, 0);
  Add(4, 2, AM, 1, 0, 0, 0); Add(5, 0, PR, 1, 0, 0, 0);
  Add(4, 1, B3, 1, 0, 0, 0); Add(5, 1, F3, 1, 0, 0, 0);
  Add(5, 0, B4, 1, 0, 0, 0); Add(5, 0, F4, 1, 0, 0, 0);
  Add(5, 0, B5, 1, 0, 0, 0); Add(5, 0, F5, 1, 0, 0, 0);
  // 127-128: LOAD_E
  Add(6, 2, AM, 0, 0, 0, 0); Add(8, 0, PR, 0, 0, 0, 0);
  // 129-160: LOAD_2 / LOAD_C, modes 01 and 11
  Add(6, 2, AM, 0, 0, 0, 1); Add(8, 0, PR, 0, 0, 0, 0);
  Add(3, 4, B0, 0, 0, 0, 0); Add(5, 3, F0, 0, 0, 0, 0);
  Add(3, 4, B1, 0, 0, 0, 0); Add(5, 3, F1, 0, 0, 0, 0);
  Add(3, 4, B2, 0, 0, 0, 0); Add(5, 3, F2, 0, 0, 0, 0);
  Add(4, 3, B3, 0, 0, 0, 0); Add(6, 2, F3, 0, 0, 0, 0);
  Add(7, 1, B4, 0, 0, 0, 0); Add(6, 2, F4, 0, 0, 0, 0);
  Add(8, 0, B5, 0, 0, 0, 0); Add(8, 0, F5, 0, 0, 0, 0);
  Add(5, 0, IA, 0, 0, 0, 0); Add(5, 0, IP, 0, 0, 0, 0);
  Add(6, 2, AM, 0, 0, 0, 1); Add(8, 0, PR, 0, 0, 0, 0);
  Add(6, 1, B0, 0, 0, 0, 0); Add(6, 2, F0, 0, 0, 0, 0);
  Add(6, 1, B1, 0, 0, 0, 0); Add(6, 2, F1, 0, 0, 0, 0);
  Add(6, 1, B2, 0, 0, 0, 0); Add(6, 2, F2, 0, 0, 0, 0);
  Add(6, 1, B3, 0, 0, 0, 0); Add(7, 1, F3, 0, 0, 0, 0);
  Add(8, 0, B4, 0, 0, 0, 0); Add(8, 0, F4, 0, 0, 0, 0);
  Add(8, 0, B5, 0, 0, 0, 0); Add(8, 0, F5, 0, 0, 0, 0);
  Add(5, 0, IA, 0, 0, 0, 0); Add(5, 0, IP, 0, 0, 0, 0);
  // 161-176: SETMSB_3 / SETMSB_5
  Add(0, 0, 0, 0, 0, 1, 0);
  Add(6, 2, AM, 0, 0, 0, 0); Add(8, 0, PR, 0, 0, 0, 0);
  Add(5, 3, F0, 0, 1, 0, 0); Add(5, 3, F1, 0, 1, 0, 0); Add(5, 3, F2, 0, 1, 0, 0);
  Add(5, 0, IA, 0, 0, 0, 0); Add(5, 0, IP, 0, 0, 0, 0);
  Add(0, 0, 0, 0, 0, 1, 0);
  Add(6, 2, AM, 0, 0, 0, 0); Add(8, 0, PR, 0, 0, 0, 0);
  Add(6, 2, F0, 0, 1, 0, 0); Add(6, 2, F1, 0, 1, 0, 0); Add(6, 2, F2, 0, 1, 0, 0);
  Add(5, 0, IA, 0, 0, 0, 0); Add(5, 0, IP, 0, 0, 0, 0);
  Assert(N = 177);
end;

function BitRev32(Val: LongWord): LongWord;
begin
  Val := ((Val and $FFFF0000) shr 16) or ((Val and $0000FFFF) shl 16);
  Val := ((Val and $FF00FF00) shr 8) or ((Val and $00FF00FF) shl 8);
  Val := ((Val and $F0F0F0F0) shr 4) or ((Val and $0F0F0F0F) shl 4);
  Val := ((Val and $CCCCCCCC) shr 2) or ((Val and $33333333) shl 2);
  Val := ((Val and $AAAAAAAA) shr 1) or ((Val and $55555555) shl 1);
  Result := Val;
end;

{ C's int16 wrap-around }
function S16(X: Integer): SmallInt; inline;
begin
  Result := SmallInt(Word(X and $FFFF));
end;

function Limit(S: SmallInt): SmallInt; inline;
begin
  if S > 8191 then Result := 8191
  else if S < -8192 then Result := -8192
  else Result := S;
end;

{ TSP0256 }

constructor TSP0256.Create;
begin
  SetLength(FRom, 65536);
  Reset;
end;

procedure TSP0256.LoadRom(const Data: array of Byte);
var
  I: Integer;
begin
  FillChar(FRom[0], Length(FRom), 0);
  for I := 0 to Min(High(Data), SP0256_ROM_SIZE - 1) do FRom[$1000 + I] := Data[I];
end;

procedure TSP0256.Reset;
begin
  FillChar(FFilt, SizeOf(FFilt), 0);
  FHalted := True;
  FFilt.Rpt := -1;
  FFilt.Rng := 1;
  FLrq := True;
  FAld := 0;
  FPc := 0;
  FStack := 0;
  FMode := 0;
  FPage := $1000 shl 3;
  FSilent := True;
end;

procedure TSP0256.WriteAllophone(Value: Byte);
begin
  if not FLrq then Exit;   // busy: dropped
  FLrq := False;
  FAld := Value shl 4;
end;

function TSP0256.GetB(Len: Integer): LongWord;
var
  D0, D1: LongWord;
begin
  D0 := FRom[(FPc shr 3) and $FFFF];
  D1 := FRom[((FPc + 8) shr 3) and $FFFF];
  Result := ((D1 shl 8) or D0) shr (FPc and 7);
  Inc(FPc, Len);
  Result := Result and ((1 shl Len) - 1);
end;

procedure TSP0256.RegDec;
var
  I: Integer;

  function IQ(X: Byte): SmallInt;
  begin
    if (X and $80) <> 0 then Result := QTBL[$7F and Byte(-Integer(X))]
    else Result := -QTBL[X];
  end;

begin
  with FFilt do
  begin
    Amp := (R[0] and $1F) shl ((R[0] and $E0) shr 5);
    Cnt := 0;
    Per := R[1];
    for I := 0 to 5 do
    begin
      BCoef[I] := IQ(R[2 + 2 * I]);
      FCoef[I] := IQ(R[3 + 2 * I]);
    end;
    Interp := (R[14] <> 0) or (R[15] <> 0);
  end;
end;

procedure TSP0256.Micro;
var
  Immed4, Opcode: Byte;
  Cw: Word;
  CtrlXfer: Boolean;
  Repeat_, I, J, Idx0, Idx1, Len, Shf, Prm: Integer;
  Value: ShortInt;
  Btrg: LongWord;
begin
  while FFilt.Rpt <= 0 do
  begin
    // Halted with an allophone waiting: start it
    if FHalted and not FLrq then
    begin
      FPc := LongWord(FAld) or ($1000 shl 3);
      FHalted := False;
      FLrq := True;
      FAld := 0;
      FillChar(FFilt.R, SizeOf(FFilt.R), 0);
    end;
    if FHalted then
    begin
      FFilt.Rpt := 1;
      FLrq := True;
      FAld := 0;
      FillChar(FFilt.R, SizeOf(FFilt.R), 0);
      Exit;
    end;

    Immed4 := GetB(4);
    Opcode := GetB(4);
    Repeat_ := 0;
    CtrlXfer := False;
    case Opcode of
      $0:
        if Immed4 <> 0 then
          FPage := BitRev32(Immed4) shr 13            // SETPAGE
        else
        begin
          // RTS, or HLT with nothing on the stack
          Btrg := FStack;
          FStack := 0;
          if Btrg = 0 then
          begin
            FHalted := True;
            FPc := 0;
          end
          else
            FPc := Btrg;
          CtrlXfer := True;
        end;
      $E, $D:
        begin
          // JMP, JSR
          Btrg := FPage or (BitRev32(Immed4) shr 17) or (BitRev32(GetB(8)) shr 21);
          CtrlXfer := True;
          if Opcode = $D then FStack := (FPc + 7) and not LongWord(7);
          FPc := Btrg;
        end;
      $1:
        FMode := ((Immed4 and 8) shr 2) or (Immed4 and 4) or ((Immed4 and 3) shl 4);   // SETMODE
    else
      Repeat_ := Immed4 or (FMode and $30);
    end;
    if Opcode <> 1 then FMode := FMode and $F;
    if CtrlXfer then Continue;
    if Repeat_ = 0 then Continue;

    FFilt.Rpt := Repeat_ + 1;
    I := (Opcode shl 3) or (FMode and 6);
    Idx0 := DF_IDX[I];
    Idx1 := DF_IDX[I + 1];
    if (Idx0 < 0) or (Idx1 < Idx0) then Continue;
    for I := Idx0 to Idx1 do
    begin
      Cw := DataFmt[I];
      Len := Cw and 15;
      Shf := (Cw shr 4) and 15;
      Prm := (Cw shr 8) and 15;
      if (Cw and CR_CLRA) <> 0 then
      begin
        for J := 0 to 15 do FFilt.R[J] := 0;
        FSilent := True;
      end;
      if (Cw and CR_CLR5) <> 0 then
      begin
        FFilt.R[B5] := 0;
        FFilt.R[F5] := 0;
      end;
      if Len = 0 then Continue;
      Value := ShortInt(Byte(GetB(Len)));
      if (Cw and CR_DELTA) <> 0 then
        if (Value and (1 shl (Len - 1))) <> 0 then
          Value := ShortInt(Byte(Value or (-1 shl Len)));
      if Shf <> 0 then Value := ShortInt(Byte(Value shl Shf));
      FSilent := False;
      if (Cw and CR_FIELD) <> 0 then
      begin
        FFilt.R[Prm] := Byte(FFilt.R[Prm] and not ($FF shl Shf));
        FFilt.R[Prm] := Byte(FFilt.R[Prm] or Byte(Value));
      end
      else if (Cw and CR_DELTA) <> 0 then
        FFilt.R[Prm] := Byte(FFilt.R[Prm] + Value)
      else
        FFilt.R[Prm] := Byte(Value);
    end;
    if Opcode = $F then
    begin
      // PAUSE
      FSilent := True;
      FFilt.R[1] := PER_PAUSE;
    end;
    RegDec;
    Break;
  end;
end;

{ One sample of the filter; False if the repeat count ran out first }
function TSP0256.FilterSample(out Sample: SmallInt): Boolean;
var
  DoInt, Bit: Boolean;
  Samp, J: Integer;
begin
  Result := False;
  Sample := 0;
  with FFilt do
  begin
    DoInt := False;
    Samp := 0;
    if Per <> 0 then
    begin
      if Cnt <= 0 then
      begin
        Inc(Cnt, Per);
        Samp := Amp;
        Dec(Rpt);
        DoInt := Interp;
        for J := 0 to 5 do
        begin
          ZData[J, 0] := 0;
          ZData[J, 1] := 0;
        end;
      end
      else
        Dec(Cnt);
    end
    else
    begin
      Dec(Cnt);
      if Cnt <= 0 then
      begin
        DoInt := Interp;
        Cnt := PER_NOISE;
        Dec(Rpt);
        for J := 0 to 5 do
        begin
          ZData[J, 0] := 0;
          ZData[J, 1] := 0;
        end;
      end;
      Bit := (Rng and 1) <> 0;
      Rng := Rng shr 1;
      if Bit then
      begin
        Rng := Rng xor $4001;
        Samp := Amp;
      end
      else
        Samp := -Amp;
    end;
    if DoInt then
    begin
      R[0] := Byte(R[0] + R[14]);
      R[1] := Byte(R[1] + R[15]);
      Amp := (R[0] and $1F) shl ((R[0] and $E0) shr 5);
      Per := R[1];
    end;
    if Rpt <= 0 then Exit;
    Samp := S16(Samp);
    for J := 0 to 5 do
    begin
      Samp := S16(Samp + SarLongint(Integer(BCoef[J]) * ZData[J, 1], 9));
      Samp := S16(Samp + SarLongint(Integer(FCoef[J]) * ZData[J, 0], 8));
      ZData[J, 1] := ZData[J, 0];
      ZData[J, 0] := Samp;
    end;
    Sample := Limit(Samp) shl 2;
    Result := True;
  end;
end;

function TSP0256.NextSample: SmallInt;
var
  Tries: Integer;
begin
  Result := 0;
  for Tries := 1 to 8 do
  begin
    if FFilt.Rpt <= 0 then Micro;
    if FHalted then
    begin
      // Idle: silent, and an allophone written now starts at once
      FFilt.Rpt := 0;
      Exit;
    end;
    if FSilent and (FFilt.Rpt <= 0) then Exit;
    if FilterSample(Result) then Exit;
  end;
end;

{ TCurrah }

constructor TCurrah.Create;
begin
  FChip := TSP0256.Create;
  FClockHz := 3500000;
  FClock := SP_CLOCK_LOW;
  SetLength(FOut, 1024);
  SetLength(FOutT, 1024);
end;

destructor TCurrah.Destroy;
begin
  FChip.Free;
  inherited Destroy;
end;

procedure TCurrah.LoadRoms(const CurrahFile, ChipFile: string);

  function ReadFile(const FileName: string; Size: Integer): TBytes;
  var
    S: TFileStream;
  begin
    S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      if S.Size < Size then
        raise Exception.CreateFmt('%s is %d bytes, %d expected', [ExtractFileName(FileName), S.Size, Size]);
      SetLength(Result, Size);
      S.ReadBuffer(Result[0], Size);
    finally
      S.Free;
    end;
  end;

var
  Data: TBytes;
begin
  Data := ReadFile(CurrahFile, CURRAH_ROM_SIZE);
  Move(Data[0], FRom[0], CURRAH_ROM_SIZE);
  FChip.LoadRom(ReadFile(ChipFile, SP0256_ROM_SIZE));
end;

procedure TCurrah.Reset;
begin
  FPaged := False;
  FChip.Reset;
  FClock := SP_CLOCK_LOW;
  FOutCount := 0;
  FOutPos := 0;
  FLast := 0;
end;

procedure TCurrah.Sync(T: Integer);
var
  Period: Double;
begin
  Period := FClockHz / (FClock / CLOCK_DIVIDER);
  while FChipT <= T do
  begin
    if FOutCount >= Length(FOut) then
    begin
      SetLength(FOut, FOutCount * 2);
      SetLength(FOutT, FOutCount * 2);
    end;
    FOut[FOutCount] := FChip.NextSample;
    FOutT[FOutCount] := FChipT;
    Inc(FOutCount);
    FChipT := FChipT + Period;
  end;
end;

function TCurrah.Level(T: Double): Single;
begin
  while (FOutPos < FOutCount) and (FOutT[FOutPos] <= T) do
  begin
    FLast := FOut[FOutPos];
    Inc(FOutPos);
  end;
  // The chip's 10 kHz steps smoothed a little, as by the analogue filter
  // after its DAC
  FFilter := FFilter + (FLast / 32768 - FFilter) * 0.35;
  Result := FFilter;
end;

procedure TCurrah.EndFrame(FrameT: Integer);
begin
  FChipT := FChipT - FrameT;
  FOutCount := 0;
  FOutPos := 0;
end;

procedure TCurrah.Toggle;
begin
  FPaged := not FPaged;
end;

function TCurrah.ReadRom(Addr: Word): Byte;
begin
  Result := FRom[Addr and (CURRAH_ROM_SIZE - 1)];
end;

procedure TCurrah.Write(Addr: Word; Value: Byte; T: Integer);
begin
  case Addr of
    $1000:
      begin
        Sync(T);
        FChip.WriteAllophone(Value and $3F);
      end;
    $3000:
      begin
        Sync(T);
        FClock := SP_CLOCK_LOW;
      end;
    $3001:
      begin
        Sync(T);
        FClock := SP_CLOCK_HIGH;
      end;
  end;
end;

function TCurrah.ReadStatus(T: Integer): Byte;
begin
  Sync(T);
  if FChip.Ready then Result := $FE else Result := $FF;
end;

initialization
  InitDataFmt;
end.
