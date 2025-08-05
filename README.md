# Gemma Vision

AI vision assistant for blind users. Built with Google’s Gemma 3n model to describe scenes, read text, and identify objects through voice.

## Features

- **Voice-first interface** with complete TTS feedback  
- **8BitDo controller support** for hands-free operation  
- **Offline AI processing** after initial model download  
- **Scene description** and text reading  
- **Screen reader optimized** for VoiceOver/TalkBack  

## Download

Get the latest APK from [Releases](../../releases)

## Controller Layout

| Button | Action             |
|--------|--------------------|
| F1     | Send with photo    |
| F2     | Toggle dictation   |
| F4     | What is this?      |
| F5     | Describe room      |
| F6     | Read text          |
| F7     | What do you see?   |

## Setup

1. Install APK  
2. Download AI model (~3 GB)  
3. Grant camera & mic permissions  
4. Connect an 8BitDo controller in **Keyboard Mode**, then open the 8BitDo Ultimate Software app and map your buttons as shown below:

   ![Controller Setup Instructions](assets/controller_setup.png)

## Development

```bash
git clone https://github.com/TGTech06/gemmavision.git
cd gemmavision
flutter pub get
flutter run
