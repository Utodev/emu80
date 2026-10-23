{ e80lib.dll / libe80.so: the emu80 emulation engine as a native library for a
  host application (see Emu80Api). Build: lib/build-lib.sh }
library e80lib;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Emu80Api;

exports
  emu80_version, emu80_create, emu80_destroy, emu80_last_error, emu80_set_model, emu80_get_model,
  emu80_set_next_dir, emu80_start, emu80_stop, emu80_pause, emu80_resume, emu80_reset, emu80_set_sound,
  emu80_set_turbo, emu80_attach_window, emu80_detach_window, emu80_set_display, emu80_set_frame_callback,
  emu80_get_frame, emu80_get_reg, emu80_set_reg, emu80_read_mem, emu80_write_mem, emu80_set_rom_writable,
  emu80_ram_bank_count, emu80_read_ram_bank, emu80_write_ram_bank, emu80_get_paging, emu80_write_port,
  emu80_set_slot3_bank, emu80_next_reg_get, emu80_next_reg_set, emu80_set_breakpoint, emu80_get_breakpoint,
  emu80_clear_breakpoints, emu80_step_into, emu80_step_over, emu80_run_to, emu80_get_state,
  emu80_get_break_reason, emu80_load_ram, emu80_load_file, emu80_key, emu80_set_kempston;

begin
end.
