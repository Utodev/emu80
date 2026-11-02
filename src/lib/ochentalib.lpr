{ ochentalib.dll / libochenta.so: the ochenta emulation engine as a native library for a
  host application (see OchentaApi). Build: lib/build-lib.sh }
library ochentalib;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  OchentaApi;

exports
  ochenta_version, ochenta_create, ochenta_destroy, ochenta_last_error, ochenta_set_model, ochenta_get_model,
  ochenta_set_next_dir, ochenta_start, ochenta_stop, ochenta_pause, ochenta_resume, ochenta_reset, ochenta_set_sound,
  ochenta_set_turbo, ochenta_attach_window, ochenta_detach_window, ochenta_set_display, ochenta_set_frame_callback,
  ochenta_get_frame, ochenta_get_reg, ochenta_set_reg, ochenta_read_mem, ochenta_write_mem, ochenta_set_rom_writable,
  ochenta_ram_bank_count, ochenta_read_ram_bank, ochenta_write_ram_bank, ochenta_get_paging, ochenta_write_port,
  ochenta_set_slot3_bank, ochenta_next_reg_get, ochenta_next_reg_set, ochenta_set_breakpoint, ochenta_get_breakpoint,
  ochenta_clear_breakpoints, ochenta_step_into, ochenta_step_over, ochenta_run_to, ochenta_get_state,
  ochenta_get_break_reason, ochenta_load_ram, ochenta_load_file, ochenta_key, ochenta_set_kempston;

begin
end.
