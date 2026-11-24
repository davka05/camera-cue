# Camera Cue

Camera Cue is a Mac teleprompter that tracks your place in a prepared script as you speak. The prompt expands from the camera cutout on notched MacBooks. The text rolls upward through a fixed reading band as it matches the words you say. On displays without a notch, the prompt anchors to the top of the available display area.

## Try it

1. Unzip the app and open **Camera Cue**. The supplied build is for Apple silicon Macs running macOS 14 or later.
2. Paste a script, or choose **Load sample**. Choose **English** or **한국어** for speech recognition.
3. Choose **Preview island** to try the display and arrow controls with the microphone off.
4. Choose **Start listening**, grant the macOS microphone and speech recognition permissions, and read the active cue aloud.
5. Use the panel controls to pause, step backward or forward, or close it. While the editor has focus, Command-Option-Up Arrow and Command-Option-Down Arrow also step between cues.

The app saves the current script and language locally. It uses on-device recognition when Apple reports it is available. Otherwise it uses Apple’s speech service, as shown in the editor’s status. The recognizer uses the selected language throughout a session. Frequent switches between English and Korean within a sentence need real-world testing. The panel may be visible when you share an entire screen.

## Build from source

Install Xcode or its Command Line Tools, then run:

```sh
./Support/build-app.sh
```

The script creates a locally signed application in `dist/` for your Mac’s architecture. The Swift package can also be opened in Xcode. Use the bundled build to test macOS microphone permissions.
