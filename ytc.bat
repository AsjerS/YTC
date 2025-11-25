@echo off
setlocal enabledelayedexpansion

:: ###################################################################
:: #  YouTube Video Converter                                        #
:: #                                                                 #
:: #  Converts video files to YouTube's recommended specifications,  #
:: #  using FFmpeg and FFprobe.                                      #
:: ###################################################################

cls

echo =================================================================
echo  YouTube Video Converter
echo =================================================================
echo.

:: --- 1. PRE-FLIGHT CHECKS ---

:: Check for FFmpeg and FFprobe
where ffmpeg >nul 2>nul
if %errorlevel% neq 0 (
    echo ERROR: ffmpeg.exe not found.
    echo Please place it in the same folder as this script or add it to your system's PATH.
    goto :ErrorExit
)
where ffprobe >nul 2>nul
if %errorlevel% neq 0 (
    echo ERROR: ffprobe.exe not found.
    echo Please place it in the same folder as this script or add it to your system's PATH.
    goto :ErrorExit
)

:: Check for input file (drag-and-drop)
if "%~1"=="" (
    echo ERROR: No input file detected.
    echo Please drag and drop a video file onto this script to begin.
    goto :ErrorExit
)

set "INPUT_FILE=%~1"
set "INPUT_DIR=%~dp1"
set "INPUT_NAME=%~n1"
set "OUTPUT_DIR=%INPUT_DIR%"
set "OUTPUT_FILE=%OUTPUT_DIR%%INPUT_NAME%_YouTube.mp4"
set "PASSLOG_FILE=%TEMP%\%INPUT_NAME%_ffmpeg_passlog"

:: --- 2. GET VIDEO INFORMATION WITH FFPROBE ---
echo Analyzing "%INPUT_NAME%%~x1"...
echo Please wait...

:: Get Video Stream Info (Height, Frame Rate)
for /f "tokens=1,2 delims=," %%a in ('ffprobe -v error -select_streams v:0 -show_entries "stream=height,r_frame_rate" -of "csv=p=0" "%INPUT_FILE%"') do (
    set "V_HEIGHT=%%a"
    set "V_FRAME_RATE_FRAC=%%b"
)
:: Check if the essential variables were set. If not, the file is likely invalid.
if not defined V_FRAME_RATE_FRAC (
    echo ERROR: Could not read video resolution or frame rate from the input file.
    echo The file may be corrupt or not a valid video file.
    goto :ErrorExit
)
:: Get optional HDR Info.
set "V_COLOR_TRANSFER="
set "V_COLOR_SPACE="
for /f "tokens=1" %%a in ('ffprobe -v error -select_streams v:0 -show_entries "stream=color_transfer" -of "csv=p=0" "%INPUT_FILE%" 2^>nul') do set "V_COLOR_TRANSFER=%%a"
for /f "tokens=1" %%a in ('ffprobe -v error -select_streams v:0 -show_entries "stream=color_space" -of "csv=p=0" "%INPUT_FILE%" 2^>nul') do set "V_COLOR_SPACE=%%a"

:: Get Audio Stream Info (Channels)
set "A_CHANNELS=0"
for /f "tokens=1" %%a in ('ffprobe -v error -select_streams a:0 -show_entries "stream=channels" -of "csv=p=0" "%INPUT_FILE%" 2^>nul') do (
    set "A_CHANNELS=%%a"
)

if %A_CHANNELS% equ 0 (
    echo.
    echo WARNING: No audio stream detected in the input file.
    echo The output file will have no audio.
    timeout /t 2 /nobreak >nul
)

:: Get Duration
for /f "tokens=1 delims=." %%a in ('ffprobe -v error -show_entries format^=duration -of default^=noprint_wrappers^=1:nokey^=1 "%INPUT_FILE%"') do (
    set "DURATION=%%a"
)

:: --- 3. PROCESS PROBED DATA ---

:: Separate frame rate fraction into numerator and denominator for precise calculations
set "V_FR_NUM=" & set "V_FR_DEN="
for /f "tokens=1,2 delims=/" %%a in ("%V_FRAME_RATE_FRAC%") do (
    set "V_FR_NUM=%%a"
    set "V_FR_DEN=%%b"
)

:: If V_FR_DEN is empty, the frame rate was likely a whole number (e.g., "60" not "60/1")
if not defined V_FR_DEN set "V_FR_DEN=1"

:: Safety check in case ffprobe returned an invalid frame rate value
if not defined V_FR_NUM (
    echo ERROR: Failed to parse frame rate value '%V_FRAME_RATE_FRAC%'.
    goto :ErrorExit
)

:: Calculate a rounded integer frame rate for display and HFR check
set /a V_FRAME_RATE=(V_FR_NUM + V_FR_DEN / 2) / V_FR_DEN

:: Determine if High Frame Rate (HFR)
set IS_HFR=0
if %V_FRAME_RATE% gtr 40 set IS_HFR=1

:: Determine if HDR
set IS_HDR=0
if "%V_COLOR_TRANSFER%"=="smpte2084" set IS_HDR=1
if "%V_COLOR_TRANSFER%"=="arib-std-b67" set IS_HDR=1
if "%V_COLOR_SPACE%"=="bt2020nc" set IS_HDR=1

:: Set recommended Audio Bitrate based on channel count
set A_BITRATE_REC=384
if %A_CHANNELS% equ 1 set A_BITRATE_REC=128
if %A_CHANNELS% gtr 2 set A_BITRATE_REC=512

:: Set recommended Video Bitrate based on height, frame rate, and HDR
set "BACK_TO_THE_BITRATE=0"
:BitrateCalculation
set V_BITRATE_REC=8
if %IS_HDR% equ 1 (
    echo Detected HDR content. Using HDR bitrate table.
    if %V_HEIGHT% gtr 4320 (if %IS_HFR% equ 0 (set V_BITRATE_REC=200) else (set V_BITRATE_REC=300))
    if %V_HEIGHT% leq 4320 if %V_HEIGHT% gtr 2160 (if %IS_HFR% equ 0 (set V_BITRATE_REC=150) else (set V_BITRATE_REC=200))
    if %V_HEIGHT% leq 2160 if %V_HEIGHT% gtr 1440 (if %IS_HFR% equ 0 (set V_BITRATE_REC=50) else (set V_BITRATE_REC=80))
    if %V_HEIGHT% leq 1440 if %V_HEIGHT% gtr 1080 (if %IS_HFR% equ 0 (set V_BITRATE_REC=20) else (set V_BITRATE_REC=30))
    if %V_HEIGHT% leq 1080 if %V_HEIGHT% gtr 720 (if %IS_HFR% equ 0 (set V_BITRATE_REC=10) else (set V_BITRATE_REC=15))
    if %V_HEIGHT% leq 720 (if %IS_HFR% equ 0 (set V_BITRATE_REC=7) else (set V_BITRATE_REC=10))
) else (
    echo Detected SDR content. Using SDR bitrate table.
    if %V_HEIGHT% gtr 4320 (if %IS_HFR% equ 0 (set V_BITRATE_REC=160) else (set V_BITRATE_REC=240))
    if %V_HEIGHT% leq 4320 if %V_HEIGHT% gtr 2160 (if %IS_HFR% equ 0 (set V_BITRATE_REC=120) else (set V_BITRATE_REC=180))
    if %V_HEIGHT% leq 2160 if %V_HEIGHT% gtr 1440 (if %IS_HFR% equ 0 (set V_BITRATE_REC=40) else (set V_BITRATE_REC=60))
    if %V_HEIGHT% leq 1440 if %V_HEIGHT% gtr 1080 (if %IS_HFR% equ 0 (set V_BITRATE_REC=16) else (set V_BITRATE_REC=24))
    if %V_HEIGHT% leq 1080 if %V_HEIGHT% gtr 720 (if %IS_HFR% equ 0 (set V_BITRATE_REC=8) else (set V_BITRATE_REC=12))
    if %V_HEIGHT% leq 720 if %V_HEIGHT% gtr 480 (if %IS_HFR% equ 0 (set V_BITRATE_REC=5) else (set V_BITRATE_REC=8))
    if %V_HEIGHT% leq 480 if %V_HEIGHT% gtr 360 (if %IS_HFR% equ 0 (set V_BITRATE_REC=3) else (set V_BITRATE_REC=4))
    if %V_HEIGHT% leq 360 (if %IS_HFR% equ 0 (set V_BITRATE_REC=1) else (set V_BITRATE_REC=2))
)
if "%BACK_TO_THE_BITRATE%"=="1" goto :VideoQualityMenu

:: Set the default encoding mode. This will be changed if the user selects "Lossless".
set "ENCODE_MODE=BITRATE"

:: --- 4. USER INTERACTION MENUS ---

:UpscaleMenu
cls
echo =================================================================
echo  Step 1: Resolution Upscaling
echo =================================================================
echo.
echo Current Resolution: %V_HEIGHT%p
echo.
echo Upscaling to 2x resolution ^(e.g. 720p -^> 1440p^) tricks YouTube
echo into giving higher quality, but can give diminishing returns
echo at resolutions higher than 1080p.
echo.
echo   [1] Keep Original Resolution (%V_HEIGHT%p) (Default)
set /a UPSCALED_HEIGHT = V_HEIGHT * 2
echo   [2] Upscale 2x (%UPSCALED_HEIGHT%p)
echo.

:: User input handling
set "USER_CHOICE="
set "SCALE_FILTER="
set /p USER_CHOICE="Select an option [Default is 1]: "
if "%USER_CHOICE%"=="" (
    set USER_CHOICE=1
    goto :VideoQualityMenu
)
if "%USER_CHOICE%"=="1" (
    goto :VideoQualityMenu
)
if "%USER_CHOICE%"=="2" (
    set "SCALE_FILTER=-vf scale=iw*2:ih*2:flags=lanczos"
    set "V_HEIGHT=%UPSCALED_HEIGHT%"
    set "BACK_TO_THE_BITRATE=1"
    goto :BitrateCalculation
)
echo.
echo Invalid option: "%USER_CHOICE%". Please enter 1 or 2.
timeout /t 2 /nobreak >nul
goto :UpscaleMenu

:VideoQualityMenu
cls
echo =================================================================
echo  Step 2: Choose Video Quality
echo =================================================================
echo.

:: Calculate estimated file sizes
set /a V_BITRATE_NORMAL_KBPS = %V_BITRATE_REC% * 1000
set /a V_BITRATE_HALVED_KBPS = V_BITRATE_NORMAL_KBPS / 2
set /a V_BITRATE_DOUBLED_KBPS = V_BITRATE_NORMAL_KBPS * 2

set /a TOTAL_KBPS_HALVED = V_BITRATE_HALVED_KBPS + A_BITRATE_REC
set /a TOTAL_KBPS_NORMAL = V_BITRATE_NORMAL_KBPS + A_BITRATE_REC
set /a TOTAL_KBPS_DOUBLED = V_BITRATE_DOUBLED_KBPS + A_BITRATE_REC

set /a SIZE_MB_HALVED = (TOTAL_KBPS_HALVED * DURATION) / 8 / 1024
set /a SIZE_MB_NORMAL = (TOTAL_KBPS_NORMAL * DURATION) / 8 / 1024
set /a SIZE_MB_DOUBLED = (TOTAL_KBPS_DOUBLED * DURATION) / 8 / 1024

:: Convert kbps to Mbps for display
set /a Mbps_INT = V_BITRATE_HALVED_KBPS / 1000
set /a Mbps_DEC = (V_BITRATE_HALVED_KBPS %% 1000) / 100
echo   [1] Halved Bitrate  (%Mbps_INT%.%Mbps_DEC% Mbps) - Faster Uploads (Est: ~%SIZE_MB_HALVED% MB)

set /a Mbps_INT = V_BITRATE_NORMAL_KBPS / 1000
set /a Mbps_DEC = (V_BITRATE_NORMAL_KBPS %% 1000) / 100
echo   [2] Normal Bitrate  (%Mbps_INT%.%Mbps_DEC% Mbps) - High Quality   (Est: ~%SIZE_MB_NORMAL% MB) (Default)

set /a Mbps_INT = V_BITRATE_DOUBLED_KBPS / 1000
set /a Mbps_DEC = (V_BITRATE_DOUBLED_KBPS %% 1000) / 100
echo   [3] Doubled Bitrate (%Mbps_INT%.%Mbps_DEC% Mbps) - Insane Quality (Est: ~%SIZE_MB_DOUBLED% MB)
echo.
echo   [4] Lossless - Perfect Quality (Est: Unknown, VERY large file)
echo   [5] Custom Bitrate...
echo.

:: User input handling
set "USER_CHOICE="
set /p USER_CHOICE="Select an option [Default is 2]: "
if "%USER_CHOICE%"=="" set USER_CHOICE=2
if "%USER_CHOICE%"=="1" set FINAL_V_BITRATE=%V_BITRATE_HALVED_KBPS%& goto :EncoderMenu
if "%USER_CHOICE%"=="2" set FINAL_V_BITRATE=%V_BITRATE_NORMAL_KBPS%& goto :EncoderMenu
if "%USER_CHOICE%"=="3" set FINAL_V_BITRATE=%V_BITRATE_DOUBLED_KBPS%& goto :EncoderMenu
if "%USER_CHOICE%"=="4" set "ENCODE_MODE=LOSSLESS"& goto :EncoderMenu
if "%USER_CHOICE%"=="5" goto :CustomBitrateMenu
echo.
echo Invalid option: "%USER_CHOICE%". Please enter 1, 2, 3, 4 or 5.
timeout /t 2 /nobreak >nul
goto :VideoQualityMenu

:CustomBitrateMenu
cls
echo =================================================================
echo  Step 2a: Enter Custom Bitrate
echo =================================================================
echo.
set /p CUSTOM_MBPS="Enter desired video bitrate in Mbps (e.g., 20): "

:: Validate input is a number greater than 0
set /a CHECK_BITRATE=0
set /a CHECK_BITRATE=%CUSTOM_MBPS%
if %CHECK_BITRATE% leq 0 (
    echo.
    echo Invalid input. Please enter a positive number.
    timeout /t 2 /nobreak >nul
    goto :CustomBitrateMenu
)

:: Convert Mbps to kbps for FFmpeg
set /a FINAL_V_BITRATE = %CUSTOM_MBPS% * 1000
goto :EncoderMenu

:EncoderMenu
cls
echo =================================================================
echo  Step 3: Choose Encoder
echo =================================================================
echo.
echo If you have a supported GPU, hardware (GPU) encoding is often a
echo lot faster than software (CPU) encoding.
echo It's recommended to use hardware encoding whenever possible.
echo.
echo NOTE: If you selected "Lossless" in Step 2, CPU will always be
echo used to ensure data integrity.
echo.
echo   [1] CPU (x264) (Default)
echo   [2] GPU - NVIDIA (NVENC)
echo   [3] GPU - AMD (AMF)
echo   [4] GPU - Intel (QSV)
echo.

:: User input handling
set "USER_CHOICE="
set "ENCODER_TYPE="
set "ENCODER_LIB="
set /p USER_CHOICE="Select an option [Default is 1]: "
if "%USER_CHOICE%"=="" set USER_CHOICE=1
if "%USER_CHOICE%"=="1" (
    set "ENCODER_TYPE=CPU"
    set "ENCODER_LIB=libx264"
    goto :SpeedPresetMenu
)
if "%USER_CHOICE%"=="2" (
    set "ENCODER_TYPE=NVIDIA"
    set "ENCODER_LIB=h264_nvenc"
    goto :SpeedPresetMenu
)
if "%USER_CHOICE%"=="3" (
    set "ENCODER_TYPE=AMD"
    set "ENCODER_LIB=h264_amf"
    goto :SpeedPresetMenu
)
if "%USER_CHOICE%"=="4" (
    set "ENCODER_TYPE=INTEL"
    set "ENCODER_LIB=h264_qsv"
    goto :SpeedPresetMenu
)
if "%ENCODE_MODE%"=="LOSSLESS" (
    if not "%ENCODER_TYPE%"=="CPU" (
        echo.
        set "ENCODER_TYPE=CPU"
        set "ENCODER_LIB=libx264"
    )
    goto :SpeedPresetMenu
)
echo.
echo Invalid option: "%USER_CHOICE%". Please enter 1, 2, 3 or 4.
timeout /t 2 /nobreak >nul
goto :EncoderMenu

:SpeedPresetMenu
cls
echo =================================================================
echo  Step 4: Choose Encoding Preset (for %ENCODER_TYPE%)
echo =================================================================
echo.
echo Choose your balance between speed and quality, where Slow gives
echo the highest quality, and Fast the lowest. It's generally not
echo recommended to use Fast, as you'll likely be limited by disk speed.
echo.
if "%ENCODER_TYPE%"=="CPU" (
    echo Actual x264 presets: Fast=superfast, Medium=faster, Slow=medium
)
if "%ENCODER_TYPE%"=="NVIDIA" (
    echo Actual NVENC presets: Fast=p2, Medium=p4, Slow=p7
)
if "%ENCODER_TYPE%"=="AMD" (
    echo Actual AMF presets: Fast=speed, Medium=balanced, Slow=quality
)
if "%ENCODER_TYPE%"=="INTEL" (
    echo Actual QSV presets: Fast=veryfast, Medium=medium, Slow=veryslow
)
echo.
echo   [1] Fast
echo   [2] Medium (Default)
echo   [3] Slow
echo.

:: User input handling
set "USER_CHOICE="
set /p USER_CHOICE="Select an option [Default is 2]: "
if "%USER_CHOICE%"=="" set USER_CHOICE=2
if "%ENCODER_TYPE%"=="CPU" (
    if "%USER_CHOICE%"=="1" set "FINAL_PRESET=superfast"& goto :PreAudioMenu
    if "%USER_CHOICE%"=="2" set "FINAL_PRESET=faster"& goto :PreAudioMenu
    if "%USER_CHOICE%"=="3" set "FINAL_PRESET=medium"& goto :PreAudioMenu
    echo.
    echo Invalid option: "%USER_CHOICE%". Please enter 1, 2 or 3.
    timeout /t 2 /nobreak >nul
    goto :SpeedPresetMenu
)
if "%ENCODER_TYPE%"=="NVIDIA" (
    if "%USER_CHOICE%"=="1" set "FINAL_PRESET=p2"& goto :PreAudioMenu
    if "%USER_CHOICE%"=="2" set "FINAL_PRESET=p5"& goto :PreAudioMenu
    if "%USER_CHOICE%"=="3" set "FINAL_PRESET=p7"& goto :PreAudioMenu
    echo.
    echo Invalid option: "%USER_CHOICE%". Please enter 1, 2 or 3.
    timeout /t 2 /nobreak >nul
    goto :SpeedPresetMenu
)
if "%ENCODER_TYPE%"=="AMD" (
    if "%USER_CHOICE%"=="1" set "FINAL_PRESET=speed"& goto :PreAudioMenu
    if "%USER_CHOICE%"=="2" set "FINAL_PRESET=balanced"& goto :PreAudioMenu
    if "%USER_CHOICE%"=="3" set "FINAL_PRESET=quality"& goto :PreAudioMenu
    echo.
    echo Invalid option: "%USER_CHOICE%". Please enter 1, 2 or 3.
    timeout /t 2 /nobreak >nul
    goto :SpeedPresetMenu
)
if "%ENCODER_TYPE%"=="INTEL" (
    if "%USER_CHOICE%"=="1" set "FINAL_PRESET=veryfast"& goto :PreAudioMenu
    if "%USER_CHOICE%"=="2" set "FINAL_PRESET=medium"& goto :PreAudioMenu
    if "%USER_CHOICE%"=="3" set "FINAL_PRESET=veryslow"& goto :PreAudioMenu
    echo.
    echo Invalid option: "%USER_CHOICE%". Please enter 1, 2 or 3.
    timeout /t 2 /nobreak >nul
    goto :SpeedPresetMenu
)

:PreAudioMenu
:: Check for audio skipping
if %A_CHANNELS% equ 0 (
    goto :OutputPathMenu
) else (
    goto :AudioMenu
)

:AudioMenu
cls
echo =================================================================
echo  Step 5: Choose Audio Format
echo =================================================================
echo.

:: --- Calculate bitrates for menu display ---
set OPUS_BITRATE_KBPS=160
if %A_CHANNELS% gtr 2 set OPUS_BITRATE_KBPS=512
set /a WAV_BITRATE_KBPS = 48 * 16 * A_CHANNELS

echo   [1] Opus - %OPUS_BITRATE_KBPS% kbps (Very High Quality, Efficient) (Default)
echo   [2] WAV  - %WAV_BITRATE_KBPS% kbps (Lossless, Large File Size) (Experimental)
echo.

:: User input handling
set "USER_CHOICE="
set /p USER_CHOICE="Select an option [Default is 1]: "
if "%USER_CHOICE%"=="" set USER_CHOICE=1
set "AUDIO_MAPPING_MODE=PASSTHROUGH"
if "%USER_CHOICE%"=="1" (
    set FINAL_A_CODEC=libopus
    set FINAL_A_BITRATE=%OPUS_BITRATE_KBPS%
    if %A_CHANNELS% gtr 2 goto :AudioMappingMenu
    goto :OutputPathMenu
)
if "%USER_CHOICE%"=="2" (
    set FINAL_A_CODEC=pcm_s16le
    set FINAL_A_BITRATE=%WAV_BITRATE_KBPS%
    if %A_CHANNELS% gtr 2 goto :AudioMappingMenu
    goto :OutputPathMenu
)
echo.
echo Invalid option: "%USER_CHOICE%". Please enter 1 or 2.
timeout /t 2 /nobreak >nul
goto :AudioMenu

:AudioMappingMenu
cls
echo =================================================================
echo  Step 5a: Choose Surround Sound Format
echo =================================================================
echo.
echo Your source file has surround sound (%A_CHANNELS% channels).
echo For YouTube, you must provide a Stereo track. You can optionally
echo also provide a 5.1 surround track.
echo.
echo   [1] Downmix to Stereo (Single Audio Track)
echo   [2] Create "Stereo + 5.1" (Two Audio Tracks) - RECOMMENDED
echo.

:: User input handling
set "USER_CHOICE="
set /p USER_CHOICE="Select an option [Default is 2]: "
if "%USER_CHOICE%"=="" set USER_CHOICE=2
if "%USER_CHOICE%"=="1" (
    set "AUDIO_MAPPING_MODE=STEREO_ONLY"
    goto :OutputPathMenu
)
if "%USER_CHOICE%"=="2" (
    set "AUDIO_MAPPING_MODE=STEREO_PLUS_51"
    goto :OutputPathMenu
)
echo.
echo Invalid option: "%USER_CHOICE%". Please enter 1 or 2.
timeout /t 2 /nobreak >nul
goto :AudioMappingMenu

:OutputPathMenu
cls
echo =================================================================
echo  Step 6: Set Output Location
echo =================================================================
echo.
echo The final video will be saved as "%INPUT_NAME%_YouTube.mp4"
echo in the directory you specify.
echo.
echo Default location:
echo %INPUT_DIR%
echo.
set /p OUTPUT_DIR_USER="Press ENTER for default, or type a new path and press ENTER: "
if not "%OUTPUT_DIR_USER%"=="" (
    set "OUTPUT_DIR=%OUTPUT_DIR_USER%"
    :: Ensure path ends with a backslash
    if not "%OUTPUT_DIR:~-1%"=="\" set "OUTPUT_DIR=%OUTPUT_DIR%\"
)
set "OUTPUT_FILE=%OUTPUT_DIR%%INPUT_NAME%_YouTube.mp4"

:Confirmation
cls
:: Calculate GOP size (half the frame rate), rounding to the nearest integer
set /a GOP_SIZE_DEN = V_FR_DEN * 2
set /a GOP_SIZE = (V_FR_NUM + GOP_SIZE_DEN / 2) / GOP_SIZE_DEN
if %GOP_SIZE% lss 1 set GOP_SIZE=1

:: Build Final FFmpeg Video Parameters
if "%ENCODE_MODE%"=="LOSSLESS" (
    set "FFMPEG_VIDEO_PARAMS=-c:v libx264 -profile:v high -preset %FINAL_PRESET% -qp 0 -g %GOP_SIZE% -keyint_min %GOP_SIZE% -bf 2 %SCALE_FILTER% -pix_fmt yuv420p"
) else (
    set "FFMPEG_VIDEO_PARAMS=-c:v %ENCODER_LIB% -profile:v high -preset %FINAL_PRESET% -b:v %FINAL_V_BITRATE%k %SCALE_FILTER% -g %GOP_SIZE% -keyint_min %GOP_SIZE% -bf 2 -pix_fmt yuv420p"
)

:: Conditionally set audio parameters based on the chosen codec and mapping
if %A_CHANNELS% equ 0 (
    set "FFMPEG_AUDIO_PARAMS=-an"
) else (
    if "%AUDIO_MAPPING_MODE%"=="STEREO_PLUS_51" (
        if "%FINAL_A_CODEC%"=="pcm_s16le" (
            set "FFMPEG_AUDIO_PARAMS=-map 0:a:0 -c:a:0 %FINAL_A_CODEC% -ac:a:0 2 -map 0:a:0 -c:a:1 %FINAL_A_CODEC% -ac:a:1 6"
        ) else (
            set "A_BITRATE_STEREO=160"
            set "A_BITRATE_51=512"
            set "FFMPEG_AUDIO_PARAMS=-map 0:a:0 -c:a:0 %FINAL_A_CODEC% -b:a:0 %A_BITRATE_STEREO%k -ac:a:0 2 -map 0:a:0 -c:a:1 %FINAL_A_CODEC% -b:a:1 %A_BITRATE_51%k -ac:a:1 6"
        )
    ) else (
        if "%AUDIO_MAPPING_MODE%"=="STEREO_ONLY" (
            set "A_BITRATE_STEREO=160"
            if "%FINAL_A_CODEC%"=="pcm_s16le" (
                set "FFMPEG_AUDIO_PARAMS=-map 0:a:0 -c:a %FINAL_A_CODEC% -ac 2"
            ) else (
                set "FFMPEG_AUDIO_PARAMS=-map 0:a:0 -c:a %FINAL_A_CODEC% -b:a %A_BITRATE_STEREO%k -ac 2"
            )
        ) else (
            :: This block handles the PASSTHROUGH case for existing stereo/mono
            if "%FINAL_A_CODEC%"=="pcm_s16le" (
                set "FFMPEG_AUDIO_PARAMS=-map 0:a:0 -c:a %FINAL_A_CODEC% -ar 48000"
            ) else (
                set "FFMPEG_AUDIO_PARAMS=-map 0:a:0 -c:a %FINAL_A_CODEC% -b:a %FINAL_A_BITRATE%k -ar 48000"
            )
        )
    )
)

echo =================================================================
echo  Summary ^& Confirmation
echo =================================================================
echo.
echo   Input File:     "%INPUT_FILE%"
echo   Resolution:     %V_HEIGHT%p
:: Fancy FPS displayer
set /a FR_REMAINDER = %V_FR_NUM% %% %V_FR_DEN%
if %FR_REMAINDER% equ 0 goto :DisplayWholeFps
set /a FR_SCALED = (%V_FR_NUM% * 100) / %V_FR_DEN%
set /a FR_INT = %FR_SCALED% / 100
set /a FR_DEC = %FR_SCALED% %% 100
if %FR_DEC% lss 10 set FR_DEC=0%FR_DEC%
echo   Frame Rate:     %FR_INT%.%FR_DEC% fps
goto :ContinueSummary1
:DisplayWholeFps
set /a FR_DISPLAY = %V_FR_NUM% / %V_FR_DEN%
echo   Frame Rate:     %FR_DISPLAY% fps
:ContinueSummary1
echo   Duration:       %DURATION% seconds
echo.
echo   ---------------------------------------------------------------
echo   Output Settings:
echo   ---------------------------------------------------------------
echo   Container:      MP4 (Fast Start)
echo   Video Codec:    H.264 (%ENCODER_LIB% @ %FINAL_PRESET%)
echo   Settings:       High, 4:2:0, 2 B-Frames, Closed GOP
echo   GOP Size:       %GOP_SIZE%
:: Video bitrate display decider
if "%ENCODE_MODE%"=="LOSSLESS" (
    echo   Video Quality:  Lossless (QP 0)
) else (
    set /a B_INT = %FINAL_V_BITRATE% / 1000
    set /a B_DEC = (%FINAL_V_BITRATE% %% 1000) / 100
    echo   Video Bitrate:  %B_INT%.%B_DEC% Mbps
)
echo.
:: Audio info display decider
if %A_CHANNELS% equ 0 (
    echo   Audio:          None ^(Source has no audio track^)
) else (
    if "%AUDIO_MAPPING_MODE%"=="STEREO_PLUS_51" (
        echo   Audio Tracks:   2 ^(Stereo + 5.1^)
        echo   Audio Codec:    %FINAL_A_CODEC%
        if "%FINAL_A_CODEC%"=="pcm_s16le" (
            echo   Audio Quality:  Lossless
        ) else (
            echo   Bitrates:       %A_BITRATE_STEREO%k ^(Stereo^), %A_BITRATE_51%k ^(5.1^)
        )
        echo   Sample Rate:    48 kHz
    ) else (
        if "%AUDIO_MAPPING_MODE%"=="STEREO_ONLY" (
            echo   Audio Tracks:   1 ^(Stereo Downmix^)
            echo   Audio Codec:    %FINAL_A_CODEC%
            if "%FINAL_A_CODEC%"=="pcm_s16le" (
                echo   Audio Quality:  Lossless
            ) else (
                echo   Audio Bitrate:  %A_BITRATE_STEREO%k
            )
            echo   Sample Rate:    48 kHz
        ) else (
            echo   Audio Tracks:   1 ^(%A_CHANNELS% channels^)
            echo   Audio Codec:    %FINAL_A_CODEC%
            if "%FINAL_A_CODEC%"=="pcm_s16le" (
                echo   Audio Data Rate: %FINAL_A_BITRATE% kbps ^(Lossless^)
            ) else (
                echo   Audio Bitrate:  %FINAL_A_BITRATE% kbps
            )
            echo   Sample Rate:    48 kHz
        )
    )
)
echo.
echo   ---------------------------------------------------------------
echo   Output Location: "%OUTPUT_FILE%"
echo   ---------------------------------------------------------------
echo.

:: User input handling
set "USER_CHOICE="
set /p USER_CHOICE="Start the conversion? [Y/n]: "
if "%USER_CHOICE%"=="" set USER_CHOICE=Y
if /i "%USER_CHOICE%"=="N" (
    echo Conversion cancelled by user.
    goto :End
)
if /i not "%USER_CHOICE%"=="Y" (
    echo Invalid choice. Aborting.
    goto :End
)

:: --- 5. START THE FFMPEG PROCESS ---
cls
echo =================================================================
echo  Starting Conversion... This may take a long time.
echo =================================================================
echo.

set "DO_2PASS=0"
if "%ENCODE_MODE%"=="BITRATE" (
    if "%ENCODER_TYPE%"=="CPU" set "DO_2PASS=1"
)
set "SILENT_FLAGS=-hide_banner -loglevel error -stats"
if "%DO_2PASS%"=="0" (
    echo --- Encoding in a single pass ^(%ENCODER_TYPE% / %ENCODE_MODE%^)... ---
    ffmpeg %SILENT_FLAGS% -i "%INPUT_FILE%" %FFMPEG_VIDEO_PARAMS% %FFMPEG_AUDIO_PARAMS% -map 0:a:0? -movflags +faststart "%OUTPUT_FILE%"
) else (
    echo --- Pass 1 of 2: Analyzing video... ---
    ffmpeg %SILENT_FLAGS% -y -i "%INPUT_FILE%" %FFMPEG_VIDEO_PARAMS% -pass 1 -passlogfile "%PASSLOG_FILE%" -an -f mp4 NUL
    if !errorlevel! neq 0 (
        echo.
        echo ERROR: FFmpeg Pass 1 failed!
        goto :ErrorExit
    )
    echo.
    echo --- Pass 2 of 2: Encoding final video with audio... ---
    ffmpeg %SILENT_FLAGS% -i "%INPUT_FILE%" %FFMPEG_VIDEO_PARAMS% -pass 2 -passlogfile "%PASSLOG_FILE%" %FFMPEG_AUDIO_PARAMS% -movflags +faststart "%OUTPUT_FILE%"
)
if !errorlevel! neq 0 (
    echo.
    echo.
    echo ERROR: FFmpeg conversion failed!
    goto :ErrorExit
)

:: --- 6. CLEANUP ---
echo.
echo Cleaning up temporary files...
del "%PASSLOG_FILE%-0.log" >nul 2>nul
del "%PASSLOG_FILE%-0.log.mbtree" >nul 2>nul

echo.
echo =================================================================
echo  Conversion Complete!
echo =================================================================
echo Output file is located at:
echo "%OUTPUT_FILE%"
goto :End


:ErrorExit
echo.
echo An error occurred. The script will now exit.

:End
echo.
pause
endlocal