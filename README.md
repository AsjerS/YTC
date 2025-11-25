# YouTube Converter (for uploading)

A program to convert your videos to a format that YouTube really likes, for the highest possible quality on your videos.

I made this because most video editors (especially free versions) usually don't give you the control you might want to get a perfect video for YouTube.

## Installation

Make sure to have both FFmpeg and FFprobe installed in your PATH or in the same directory as the .bat script.

Download `ytc.bat` from the top of this page and place on your desktop for easy access (or anywhere you like really).

## Features

- Easy drag-and-drop system
- Video upscaling using Lanczos (e.g 1080p -> 4K) (optional)
- Strict, [guideline following](https://support.google.com/youtube/answer/1722171) settings
- Automatic recommended bitrate calculation (optional)
- Hardware acceleration support (NVENC/AMF/QSV)
- HDR and 5.1 surround support

## Usage

Drop any video file on it and follow the instructions on screen.

For the best quality, record your footage at a very high bitrate (or lossless), edit your video if needed, and export your video at a really high bitrate too, or lossless like with FFV1 plus PCM. This makes it so this program has a high quality file to begin converting with (because it can't create quality if you don't feed it quality).