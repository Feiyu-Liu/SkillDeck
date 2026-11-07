#define AppName "SkillDeck"
#define AppPublisher "Feiyu Liu"
#define AppExeName "SkillDeck.exe"

#ifndef AppVersion
  #define AppVersion "1.0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist\windows"
#endif

[Setup]
AppId={{4B88C1CF-8933-4C84-BDCE-1980AA1C73A4}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
SetupIconFile=..\..\runner\resources\app_icon.ico
DefaultDirName={localappdata}\Programs\SkillDeck
DefaultGroupName={#AppName}
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=skilldeck-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
CloseApplications=force
RestartApplications=no
UninstallDisplayIcon={app}\{#AppExeName}
WizardStyle=modern
; Broadcast the PATH change so new terminals pick up the skilldeck CLI.
ChangesEnvironment=yes

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Registry]
; The App keeps the skilldeck CLI at %USERPROFILE%\.skilldeck\bin (ADR-0111).
; Add it to the user PATH once; no administrator rights are needed.
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};%USERPROFILE%\.skilldeck\bin"; Check: NeedsSkillDeckCliPath

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall

[Code]
function NeedsSkillDeckCliPath(): Boolean;
var
  Current: string;
begin
  if not RegQueryStringValue(HKCU, 'Environment', 'Path', Current) then
  begin
    Result := True;
    exit;
  end;
  { Match either the literal or the expanded form, case-insensitively. }
  Result :=
    (Pos(';' + Uppercase('%USERPROFILE%\.skilldeck\bin') + ';',
      ';' + Uppercase(Current) + ';') = 0) and
    (Pos(';' + Uppercase(ExpandConstant('{%USERPROFILE}') + '\.skilldeck\bin') + ';',
      ';' + Uppercase(Current) + ';') = 0);
end;
