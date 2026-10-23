{ The native library's API (Emu80Api), called as a host would but from Pascal:
  create, start, pause, registers, memory (logical and RAM banks), paging,
  breakpoints, stepping, frames and the handles' checks. The C# host demo
  (tests/csharp) does the same through P/Invoke, with the screen. Needs the
  ROMs:

    libtest <roms folder> }
program libtest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Emu80Api;

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
  S: TEmu80State;
  P: TEmu80Paging;
  V: Int32;
  B: array[0..15] of Byte;
  Buf: array of Byte;
  W, Hh, I: Int32;
  Prog: array[0..7] of Byte = ($F3, $3A, $00, $C0, $D3, $FE, $18, $F9);
  Err: array[0..255] of AnsiChar;
  F1: Int64;
begin
  Check(emu80_version = 1, 'API version');
  Check(emu80_create(99, PAnsiChar(ParamStr(1))) = nil, 'an unknown model is refused');
  Check(emu80_pause(Pointer(1234)) < 0, 'an invalid handle is refused');
  H := emu80_create(2, PAnsiChar(ParamStr(1)));       // 128K
  Check(H <> nil, 'create');
  if H = nil then Halt(1);
  Check(emu80_get_model(H) = 2, 'model');
  Check(emu80_start(H) = 0, 'start');
  Sleep(600);
  emu80_get_state(H, @S);
  Check((S.Running = 1) and (S.Paused = 0) and (S.FramesLow > 10), 'running, frames come');
  F1 := S.FramesLow;
  Check(emu80_pause(H) = 0, 'pause');
  emu80_get_state(H, @S);
  Check(S.Paused = 1, 'paused');
  F1 := S.FramesLow;
  Sleep(200);
  emu80_get_state(H, @S);
  Check(S.FramesLow = F1, 'no frames while paused');

  // Registers
  Check(emu80_set_reg(H, 3, $1234) = 0, 'set HL');
  Check((emu80_get_reg(H, 3, @V) = 0) and (V = $1234), 'get HL');
  emu80_set_reg(H, 0, $A55A);
  emu80_get_reg(H, 0, @V);
  Check(V = $A55A, 'AF');
  emu80_set_reg(H, 11, $8000);
  emu80_get_reg(H, 11, @V);
  Check(V = $8000, 'PC');
  Check(emu80_set_reg(H, 99, 1) < 0, 'an unknown register is refused');

  // Memory: logical and by RAM bank
  Check(emu80_write_mem(H, $8000, @Prog[0], 8) = 8, 'write memory');
  FillChar(B, SizeOf(B), 0);
  Check((emu80_read_mem(H, $8000, @B[0], 8) = 8) and (CompareByte(B, Prog, 8) = 0), 'read memory back');
  Check(emu80_read_mem(H, $FFFF, @B[0], 4) < 0, 'reading past the end is refused');
  Check(emu80_ram_bank_count(H) = 8, 'RAM banks of a 128K');
  B[0] := 2;
  emu80_write_ram_bank(H, 0, 0, @B[0], 1);
  B[0] := 5;
  emu80_write_ram_bank(H, 1, 0, @B[0], 1);
  emu80_write_port(H, $7FFD, $10);
  emu80_get_paging(H, @P);
  Check(P.Slot3 = 0, 'bank 0 at C000');
  emu80_read_mem(H, $C000, @B[0], 1);
  Check(B[0] = 2, 'C000 shows bank 0');
  Check(emu80_write_port(H, $7FFD, $11) = 0, 'paging bank 1');
  emu80_get_paging(H, @P);
  emu80_read_mem(H, $C000, @B[0], 1);
  Check((P.Slot3 = 1) and (B[0] = 5), 'C000 shows bank 1 after paging');
  Check(emu80_set_slot3_bank(H, 3) = 0, 'slot 3 bank');
  emu80_get_paging(H, @P);
  Check(P.Slot3 = 3, 'slot 3 is bank 3');

  // Breakpoint and stepping: the loop at 8000, border from C000
  emu80_write_port(H, $7FFD, $10);
  emu80_set_reg(H, 11, $8000);
  Check(emu80_set_breakpoint(H, $8001, 1) = 0, 'breakpoint');
  Check(emu80_get_breakpoint(H, $8001) = 1, 'breakpoint read');
  Check(emu80_resume(H) = 0, 'resume');
  Sleep(400);
  emu80_get_state(H, @S);
  Check((S.Paused = 1) and (S.BreakKind = 1) and (S.PC = $8001), 'stopped at the breakpoint');
  Check(emu80_get_break_reason(H, @Err[0], SizeOf(Err)) > 0, 'a reason for the stop');
  emu80_clear_breakpoints(H);
  Check(emu80_step_into(H) = 0, 'step');
  emu80_get_reg(H, 11, @V);
  Check(V = $8004, 'one step: PC after LD A,(C000)');
  emu80_get_reg(H, 0, @V);
  Check((V shr 8) = 2, 'A holds the byte of bank 0');
  Check(emu80_run_to(H, $8006) = 0, 'run to');
  Sleep(300);
  emu80_get_reg(H, 11, @V);
  Check(V = $8006, 'run to: stopped at 8006');

  // The frame
  SetLength(Buf, 352 * 288 * 4);
  Check(emu80_get_frame(H, nil, 0, 1, @W, @Hh) = 352 * 288 * 4, 'the size a frame needs');
  Check((emu80_get_frame(H, @Buf[0], Length(Buf), 1, @W, @Hh) = 0) and (W = 352) and (Hh = 288), 'get a frame');
  V := 0;
  for I := 0 to 352 * 288 - 1 do
    if PLongWord(@Buf[0])[I] <> 0 then Inc(V);
  Check(V > 1000, 'the frame has a picture');
  Check(emu80_set_display(H, 2, 0, 0) = 0, 'display options');
  Check(emu80_set_display(H, 9, 0, 0) < 0, 'a bad deinterlace is refused');
  Check(emu80_attach_window(H, nil) < 0, 'no window to attach');

  // Keys
  Check(emu80_key(H, 30, 1) = 0, 'a key down');
  Check(emu80_key(H, 99, 1) < 0, 'a bad key is refused');
  emu80_key(H, 30, 0);

  // Model, reset, stop and start again, destroy
  Check(emu80_set_model(H, 1) = 0, 'set the 48K');
  Check(emu80_get_model(H) = 1, 'it is the 48K');
  Check(emu80_ram_bank_count(H) = 8, 'banks');
  Check(emu80_reset(H, 1) = 0, 'reset');
  Check(emu80_stop(H) = 0, 'stop');
  emu80_get_state(H, @S);
  Check(S.Running = 0, 'stopped');
  Check((emu80_start(H) = 0) and (emu80_resume(H) = 0), 'started again');
  Sleep(300);
  emu80_get_state(H, @S);
  Check((S.Running = 1) and (S.Paused = 0), 'running again');
  emu80_destroy(H);
  Check(emu80_pause(H) < 0, 'a destroyed handle is refused');
  if Failures = 0 then WriteLn('Native library API: all passed') else Halt(1);
end.
