{ The native library's API (OchentaApi), called as a host would but from Pascal:
  create, start, pause, registers, memory (logical and RAM banks), paging,
  breakpoints, stepping, frames and the handles' checks. The C# host demo
  (tests/csharp) does the same through P/Invoke, with the screen. Needs the
  ROMs:

    libtest <roms folder> }
program libtest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, OchentaApi;

var
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const What: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL  ', What);
    Inc(Failures);
  end;
end;

var
  H: Pointer;
  S: TOchentaState;
  P: TOchentaPaging;
  V: Int32;
  B: array[0..15] of Byte;
  Buf: array of Byte;
  W, Hh, I: Int32;
  Prog: array[0..7] of Byte = ($F3, $3A, $00, $C0, $D3, $FE, $18, $F9);
  Err: array[0..255] of AnsiChar;
  F1: Int64;
  H2: Pointer;
  SamDir: string;
  Rom: array[0..32767] of Byte;
  F: TFileStream;
begin
  Check(ochenta_version = 1, 'API version');
  Check(ochenta_create(99, PAnsiChar(ParamStr(1))) = nil, 'an unknown model is refused');
  Check(ochenta_pause(Pointer(1234)) < 0, 'an invalid handle is refused');
  H := ochenta_create(2, PAnsiChar(ParamStr(1)));       // 128K
  Check(H <> nil, 'create');
  if H = nil then Halt(1);
  Check(ochenta_get_model(H) = 2, 'model');
  Check(ochenta_start(H) = 0, 'start');
  Sleep(600);
  ochenta_get_state(H, @S);
  Check((S.Running = 1) and (S.Paused = 0) and (S.FramesLow > 10), 'running, frames come');
  F1 := S.FramesLow;
  Check(ochenta_pause(H) = 0, 'pause');
  ochenta_get_state(H, @S);
  Check(S.Paused = 1, 'paused');
  F1 := S.FramesLow;
  Sleep(200);
  ochenta_get_state(H, @S);
  Check(S.FramesLow = F1, 'no frames while paused');

  // Registers
  Check(ochenta_set_reg(H, 3, $1234) = 0, 'set HL');
  Check((ochenta_get_reg(H, 3, @V) = 0) and (V = $1234), 'get HL');
  ochenta_set_reg(H, 0, $A55A);
  ochenta_get_reg(H, 0, @V);
  Check(V = $A55A, 'AF');
  ochenta_set_reg(H, 11, $8000);
  ochenta_get_reg(H, 11, @V);
  Check(V = $8000, 'PC');
  Check(ochenta_set_reg(H, 99, 1) < 0, 'an unknown register is refused');

  // Memory: logical and by RAM bank
  Check(ochenta_write_mem(H, $8000, @Prog[0], 8) = 8, 'write memory');
  FillChar(B, SizeOf(B), 0);
  Check((ochenta_read_mem(H, $8000, @B[0], 8) = 8) and (CompareByte(B, Prog, 8) = 0), 'read memory back');
  Check(ochenta_read_mem(H, $FFFF, @B[0], 4) < 0, 'reading past the end is refused');
  Check(ochenta_ram_bank_count(H) = 8, 'RAM banks of a 128K');
  B[0] := 2;
  ochenta_write_ram_bank(H, 0, 0, @B[0], 1);
  B[0] := 5;
  ochenta_write_ram_bank(H, 1, 0, @B[0], 1);
  ochenta_write_port(H, $7FFD, $10);
  ochenta_get_paging(H, @P);
  Check(P.Slot3 = 0, 'bank 0 at C000');
  ochenta_read_mem(H, $C000, @B[0], 1);
  Check(B[0] = 2, 'C000 shows bank 0');
  Check(ochenta_write_port(H, $7FFD, $11) = 0, 'paging bank 1');
  ochenta_get_paging(H, @P);
  ochenta_read_mem(H, $C000, @B[0], 1);
  Check((P.Slot3 = 1) and (B[0] = 5), 'C000 shows bank 1 after paging');
  Check(ochenta_set_slot3_bank(H, 3) = 0, 'slot 3 bank');
  ochenta_get_paging(H, @P);
  Check(P.Slot3 = 3, 'slot 3 is bank 3');

  // Breakpoint and stepping: the loop at 8000, border from C000
  ochenta_write_port(H, $7FFD, $10);
  ochenta_set_reg(H, 11, $8000);
  Check(ochenta_set_breakpoint(H, $8001, 1) = 0, 'breakpoint');
  Check(ochenta_get_breakpoint(H, $8001) = 1, 'breakpoint read');
  Check(ochenta_resume(H) = 0, 'resume');
  Sleep(400);
  ochenta_get_state(H, @S);
  Check((S.Paused = 1) and (S.BreakKind = 1) and (S.PC = $8001), 'stopped at the breakpoint');
  Check(ochenta_get_break_reason(H, @Err[0], SizeOf(Err)) > 0, 'a reason for the stop');
  ochenta_clear_breakpoints(H);
  Check(ochenta_step_into(H) = 0, 'step');
  ochenta_get_reg(H, 11, @V);
  Check(V = $8004, 'one step: PC after LD A,(C000)');
  ochenta_get_reg(H, 0, @V);
  Check((V shr 8) = 2, 'A holds the byte of bank 0');
  Check(ochenta_run_to(H, $8006) = 0, 'run to');
  Sleep(300);
  ochenta_get_reg(H, 11, @V);
  Check(V = $8006, 'run to: stopped at 8006');

  // The frame
  SetLength(Buf, 352 * 288 * 4);
  Check(ochenta_get_frame(H, nil, 0, 1, @W, @Hh) = 352 * 288 * 4, 'the size a frame needs');
  Check((ochenta_get_frame(H, @Buf[0], Length(Buf), 1, @W, @Hh) = 0) and (W = 352) and (Hh = 288), 'get a frame');
  V := 0;
  for I := 0 to 352 * 288 - 1 do
    if PLongWord(@Buf[0])[I] <> 0 then Inc(V);
  Check(V > 1000, 'the frame has a picture');
  Check(ochenta_set_display(H, 2, 0, 0) = 0, 'display options');
  Check(ochenta_set_display(H, 9, 0, 0) < 0, 'a bad deinterlace is refused');
  Check(ochenta_attach_window(H, nil) < 0, 'no window to attach');

  // Keys
  Check(ochenta_key(H, 30, 1) = 0, 'a key down');
  Check(ochenta_key(H, 99, 1) < 0, 'a bad key is refused');
  ochenta_key(H, 30, 0);

  // Model, reset, stop and start again, destroy
  Check(ochenta_set_model(H, 1) = 0, 'set the 48K');
  Check(ochenta_get_model(H) = 1, 'it is the 48K');
  Check(ochenta_ram_bank_count(H) = 8, 'banks');
  Check(ochenta_reset(H, 1) = 0, 'reset');
  Check(ochenta_stop(H) = 0, 'stop');
  ochenta_get_state(H, @S);
  Check(S.Running = 0, 'stopped');
  Check((ochenta_start(H) = 0) and (ochenta_resume(H) = 0), 'started again');
  Sleep(300);
  ochenta_get_state(H, @S);
  Check((S.Running = 1) and (S.Paused = 0), 'running again');
  ochenta_destroy(H);
  Check(ochenta_pause(H) < 0, 'a destroyed handle is refused');

  // The SAM Coupe (model 11): its ROM isn't distributed, so a machine can't be made without one;
  // with one (here a made-up 32K of NOPs) the API takes it: RAM pages, keys, paging, ports
  if not FileExists(IncludeTrailingPathDelimiter(ParamStr(1)) + 'samcoupe.rom') then
    Check(ochenta_create(11, PAnsiChar(ParamStr(1))) = nil, 'a SAM Coupe without its ROM is refused');
  SamDir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'ochenta-libtest-sam';
  ForceDirectories(SamDir);
  FillChar(Rom, SizeOf(Rom), 0);
  F := TFileStream.Create(IncludeTrailingPathDelimiter(SamDir) + 'samcoupe.rom', fmCreate);
  try
    F.WriteBuffer(Rom, SizeOf(Rom));
  finally
    F.Free;
  end;
  H2 := ochenta_create(11, PAnsiChar(SamDir));
  Check(H2 <> nil, 'a SAM Coupe is created');
  if H2 <> nil then
  begin
    Check(ochenta_get_model(H2) = 11, 'it is model 11');
    Check(ochenta_ram_bank_count(H2) = 32, '32 pages of RAM (512K)');
    Check(ochenta_key(H2, 71, 1) = 0, 'the last key of the matrix goes down');
    Check(ochenta_key(H2, 72, 1) < 0, 'a key past the 72 is refused');
    ochenta_key(H2, 71, 0);
    Check(ochenta_write_port(H2, $00FB, 5) = 0, 'HMPR 5');
    Check(ochenta_get_paging(H2, @P) = 0, 'paging');
    Check((P.Slot2 = 5) and (P.Slot3 = 6) and (P.Port1FFD = 5), 'pages 5 and 6 at 8000 and C000 (HMPR in Port1FFD)');
    Check(P.Slot0 = -1, 'ROM0 at 0000');
    Check(ochenta_write_port(H2, $00FA, $24) = 0, 'LMPR with RAM at 0000');
    ochenta_get_paging(H2, @P);
    Check((P.Slot0 = 4) and (P.Slot1 = 5) and (P.Port7FFD = $24), 'pages 4 and 5 at 0000 (LMPR in Port7FFD)');
    Check(ochenta_write_port(H2, $03F8, $77) = 0, 'a CLUT entry (the high byte says which)');
    Check(ochenta_write_port(H2, $1234, 1) < 0, 'a port the SAM doesn''t have is refused');
    Check(ochenta_set_slot3_bank(H2, 3) < 0, 'the +3''s slot 3 bank means nothing on a SAM Coupe');
    ochenta_destroy(H2);
  end;
  if Failures = 0 then WriteLn('Native library API: all passed') else Halt(1);
end.
