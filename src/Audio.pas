{ Audio: 16-bit stereo sound output. Windows uses waveOut; Linux and macOS
  use SDL2, loaded at run time so the program still starts without it.
  Queuing a frame of samples blocks while enough audio is already queued,
  which paces the emulation to real time. When no audio device is available
  Write returns False and the caller paces itself. }
unit Audio;

{$mode objfpc}{$H+}

interface

uses
  SysUtils
  {$IFDEF WINDOWS}, Windows, MMSystem{$ELSE}, DynLibs{$ENDIF};

type
  TAudioOutput = class
  private
    {$IFDEF WINDOWS}
    FDevice: HWAVEOUT;
    FEvent: THandle;
    FHeaders: array of TWaveHdr;
    FBuffers: array of array of SmallInt;
    FNext: Integer;
    {$ELSE}
    FDevice: LongWord;
    FMaxQueued: LongWord;   // bytes; Write waits while more than this is queued
    FLastQueued: LongWord;
    {$ENDIF}
    FOpen: Boolean;
    FStalled: Boolean;      // device stopped consuming: caller paces by timer
  public
    constructor Create(SampleRate, BufferCount, MaxFrames: Integer);
    destructor Destroy; override;
    { Queue Count stereo frames. Returns False if audio is unavailable. }
    function Write(Samples: Pointer; Count: Integer): Boolean;
    property IsOpen: Boolean read FOpen;
  end;

implementation

{$IFNDEF WINDOWS}
type
  TSDLAudioSpec = record
    Freq: LongInt;
    Format: Word;
    Channels: Byte;
    Silence: Byte;
    Samples: Word;
    Padding: Word;
    Size: LongWord;
    Callback: Pointer;
    UserData: Pointer;
  end;
  PSDLAudioSpec = ^TSDLAudioSpec;

const
  SDL_INIT_AUDIO = $10;
  AUDIO_S16LSB = $8010;
  SDLLibraries: array[0..5] of string = (
    'libSDL2-2.0.so.0', 'libSDL2.so', 'libSDL2-2.0.0.dylib',
    '/opt/homebrew/lib/libSDL2-2.0.0.dylib', '/usr/local/lib/libSDL2-2.0.0.dylib',
    'SDL2.framework/SDL2');

var
  SDLLib: TLibHandle = NilHandle;
  SDL_InitSubSystem: function(Flags: LongWord): LongInt; cdecl;
  SDL_OpenAudioDevice: function(Device: PChar; IsCapture: LongInt; Desired, Obtained: PSDLAudioSpec;
    AllowedChanges: LongInt): LongWord; cdecl;
  SDL_PauseAudioDevice: procedure(Dev: LongWord; PauseOn: LongInt); cdecl;
  SDL_QueueAudio: function(Dev: LongWord; Data: Pointer; Len: LongWord): LongInt; cdecl;
  SDL_GetQueuedAudioSize: function(Dev: LongWord): LongWord; cdecl;
  SDL_CloseAudioDevice: procedure(Dev: LongWord); cdecl;
  SDL_ClearQueuedAudio: procedure(Dev: LongWord); cdecl;

function LoadSDL: Boolean;
var
  Name: string;
begin
  if SDLLib = NilHandle then
    for Name in SDLLibraries do
    begin
      SDLLib := LoadLibrary(Name);
      if SDLLib <> NilHandle then Break;
    end;
  if SDLLib = NilHandle then Exit(False);
  Pointer(SDL_InitSubSystem) := GetProcAddress(SDLLib, 'SDL_InitSubSystem');
  Pointer(SDL_OpenAudioDevice) := GetProcAddress(SDLLib, 'SDL_OpenAudioDevice');
  Pointer(SDL_PauseAudioDevice) := GetProcAddress(SDLLib, 'SDL_PauseAudioDevice');
  Pointer(SDL_QueueAudio) := GetProcAddress(SDLLib, 'SDL_QueueAudio');
  Pointer(SDL_GetQueuedAudioSize) := GetProcAddress(SDLLib, 'SDL_GetQueuedAudioSize');
  Pointer(SDL_CloseAudioDevice) := GetProcAddress(SDLLib, 'SDL_CloseAudioDevice');
  Pointer(SDL_ClearQueuedAudio) := GetProcAddress(SDLLib, 'SDL_ClearQueuedAudio');
  Result := Assigned(SDL_ClearQueuedAudio) and Assigned(SDL_InitSubSystem) and Assigned(SDL_OpenAudioDevice) and
    Assigned(SDL_PauseAudioDevice) and Assigned(SDL_QueueAudio) and
    Assigned(SDL_GetQueuedAudioSize) and Assigned(SDL_CloseAudioDevice);
end;
{$ENDIF}

constructor TAudioOutput.Create(SampleRate, BufferCount, MaxFrames: Integer);
{$IFDEF WINDOWS}
var
  Format: TWaveFormatEx;
  I: Integer;
{$ELSE}
var
  Want, Got: TSDLAudioSpec;
{$ENDIF}
begin
  inherited Create;
  FOpen := False;
  {$IFNDEF WINDOWS}
  if not LoadSDL or (SDL_InitSubSystem(SDL_INIT_AUDIO) <> 0) then Exit;
  FillChar(Want, SizeOf(Want), 0);
  Want.Freq := SampleRate;
  Want.Format := AUDIO_S16LSB;
  Want.Channels := 2;
  Want.Samples := 512;
  FDevice := SDL_OpenAudioDevice(nil, 0, @Want, @Got, 0);
  if FDevice = 0 then Exit;
  // Same latency as the Windows ring: BufferCount frames' worth
  FMaxQueued := (BufferCount - 1) * MaxFrames * 4;
  SDL_PauseAudioDevice(FDevice, 0);
  FOpen := True;
  {$ENDIF}
  {$IFDEF WINDOWS}
  FillChar(Format, SizeOf(Format), 0);
  Format.wFormatTag := WAVE_FORMAT_PCM;
  Format.nChannels := 2;
  Format.nSamplesPerSec := SampleRate;
  Format.wBitsPerSample := 16;
  Format.nBlockAlign := 4;
  Format.nAvgBytesPerSec := SampleRate * 4;
  FEvent := CreateEvent(nil, False, False, nil);
  if waveOutOpen(@FDevice, WAVE_MAPPER, @Format, DWORD_PTR(FEvent), 0, CALLBACK_EVENT) <> MMSYSERR_NOERROR then
    Exit;
  SetLength(FHeaders, BufferCount);
  SetLength(FBuffers, BufferCount);
  for I := 0 to BufferCount - 1 do
  begin
    SetLength(FBuffers[I], MaxFrames * 2);
    FillChar(FHeaders[I], SizeOf(TWaveHdr), 0);
    FHeaders[I].lpData := @FBuffers[I][0];
    FHeaders[I].dwBufferLength := MaxFrames * 4;
    waveOutPrepareHeader(FDevice, @FHeaders[I], SizeOf(TWaveHdr));
    FHeaders[I].dwFlags := FHeaders[I].dwFlags or WHDR_DONE;
  end;
  FNext := 0;
  FOpen := True;
  {$ENDIF}
end;

destructor TAudioOutput.Destroy;
{$IFDEF WINDOWS}
var
  I: Integer;
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  if FOpen then
  begin
    waveOutReset(FDevice);
    for I := 0 to High(FHeaders) do
      waveOutUnprepareHeader(FDevice, @FHeaders[I], SizeOf(TWaveHdr));
    waveOutClose(FDevice);
  end;
  if FEvent <> 0 then CloseHandle(FEvent);
  {$ELSE}
  if FOpen then SDL_CloseAudioDevice(FDevice);
  {$ENDIF}
  inherited Destroy;
end;

function TAudioOutput.Write(Samples: Pointer; Count: Integer): Boolean;
const
  MAX_WAIT_MS = 100;   // longer than this means the device has stalled
{$IFDEF WINDOWS}
var
  Hdr: PWaveHdr;
  Start: QWord;
begin
  Result := False;
  if not FOpen then Exit;
  Hdr := @FHeaders[FNext];
  if FStalled then
  begin
    // Don't block while stalled; resume once the device plays again
    if (Hdr^.dwFlags and WHDR_DONE) = 0 then Exit;
    FStalled := False;
  end;
  // Wait for the next buffer in the ring to finish playing
  Start := GetTickCount64;
  while (Hdr^.dwFlags and WHDR_DONE) = 0 do
  begin
    WaitForSingleObject(FEvent, 10);
    if GetTickCount64 - Start > MAX_WAIT_MS then
    begin
      FStalled := True;
      Exit;
    end;
  end;
  if Count * 2 > Length(FBuffers[FNext]) then Count := Length(FBuffers[FNext]) div 2;
  Move(Samples^, FBuffers[FNext][0], Count * 4);
  Hdr^.dwBufferLength := Count * 4;
  Hdr^.dwFlags := Hdr^.dwFlags and not WHDR_DONE;
  waveOutWrite(FDevice, Hdr, SizeOf(TWaveHdr));
  FNext := (FNext + 1) mod Length(FHeaders);
  Result := True;
end;
{$ELSE}
var
  Start: QWord;
  Queued: LongWord;
begin
  Result := False;
  if not FOpen then Exit;
  if FStalled then
  begin
    // Keep feeding without blocking; resume once the queue starts draining
    Queued := SDL_GetQueuedAudioSize(FDevice);
    if Queued >= FLastQueued then
    begin
      if Queued > FMaxQueued then SDL_ClearQueuedAudio(FDevice);
      SDL_QueueAudio(FDevice, Samples, Count * 4);
      FLastQueued := SDL_GetQueuedAudioSize(FDevice);
      Exit;
    end;
    FStalled := False;
  end;
  // Wait until the device has played down to the target latency
  Start := GetTickCount64;
  while SDL_GetQueuedAudioSize(FDevice) > FMaxQueued do
  begin
    Sleep(1);
    if GetTickCount64 - Start > MAX_WAIT_MS then
    begin
      FStalled := True;
      FLastQueued := SDL_GetQueuedAudioSize(FDevice);
      Exit;
    end;
  end;
  Result := SDL_QueueAudio(FDevice, Samples, Count * 4) = 0;
end;
{$ENDIF}

end.
