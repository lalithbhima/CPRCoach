<p align="center">
  <img src="VisionCPRCoach/assests/CPRCoachLogo.png" alt="CPR Coach logo" width="160">
</p>

<h1 align="center">CPR Coach</h1>

<p align="center">
  A multilingual, AI-powered iPhone app that guides everyday people through high-quality CPR during a real emergency and helps them practice before one ever happens.
</p>

<p align="center">
  Submitted to the <strong>Congressional App Challenge</strong> by Lalith Bhima, Bhavika Bhima, and Yihan Duan
</p>

<p align="center">
  <em>Training guidance only. Not a medical device. In a real emergency, call your local emergency number first.</em>
</p>

---

## Table of Contents

- [Overview](#overview)
  - [Problem Statement](#problem-statement)
  - [Our Solution](#our-solution)
  - [Features](#features)
- [Technical Details](#technical-details)
  - [System Architecture](#system-architecture)
  - [AI Models and What They Do](#ai-models-and-what-they-do)
  - [Computer Vision Models](#computer-vision-models)
  - [Depth and Signal Processing](#depth-and-signal-processing)
  - [Language and Voice Models](#language-and-voice-models)
  - [How the Models Work Together](#how-the-models-work-together)
  - [Scoring and Thresholds](#scoring-and-thresholds)
  - [AHA Coaching Targets](#aha-coaching-targets)
  - [Compression Quality Score](#compression-quality-score)
  - [Pressure Score](#pressure-score)
  - [CPR Error Recognition and Confidence](#cpr-error-recognition-and-confidence)
  - [Coaching Margins](#coaching-margins)
  - [Python Prototype Thresholds](#python-prototype-thresholds)
  - [Evaluation](#evaluation)
  - [Tech Stack](#tech-stack)
- [Setup and Usage](#setup-and-usage)
  - [Requirements](#requirements)
  - [Getting Started](#getting-started)
  - [Step 1: Download the Project](#step-1-download-the-project)
  - [Step 2: Add Your API Key](#step-2-add-your-api-key)
  - [Step 3: Open in Xcode](#step-3-open-in-xcode)
  - [Step 4: Set Up Signing](#step-4-set-up-signing)
  - [Step 5: Run on Your iPhone](#step-5-run-on-your-iphone)
  - [Step 6: Your First Coaching Session](#step-6-your-first-coaching-session)
  - [Running the Python Prototype](#running-the-python-prototype)
  - [Localization Tools](#localization-tools)
  - [Running Tests](#running-tests)
  - [Troubleshooting](#troubleshooting)
  - [Folder Structure](#folder-structure)
- [Project Information](#project-information)
  - [How We Used AI in Development](#how-we-used-ai-in-development)
  - [Privacy and Permissions](#privacy-and-permissions)
  - [Roadmap for CPR Coach 2.0](#roadmap-for-cpr-coach-20)
  - [Disclaimer](#disclaimer)
  - [Contact and Links](#contact-and-links)

---

# Overview

## Problem Statement

Imagine someone you love collapses right in front of you. One moment, everything feels normal. The next, their heart has stopped, and the people nearby have only seconds to act. That hesitation can be the difference between life and death. There is **no warning**, no preparation — only an emergency that needs someone to step in. Most of the time, the person who saves a life is not a doctor. It is a bystander.

| Fact | Value |
|------|-------|
| Survival boost from bystander CPR | CPR can triple the chance of survival |
| Out-of-hospital cardiac arrest survival | About 90% of people do not survive |
| People trained to perform CPR | Less than 3% of the population |
| Cardiac arrests per year in California | About 65,000 |
| Cardiac arrests per year in the United States | Over 400,000 |
| Cardiac arrests per year worldwide | About 5 million |

Most people never learn CPR because they believe it will never happen to them or someone they love. Telling people to take a class ahead of time is not enough, because there will always be people who never do. The real question is whether someone with no training can still give high-quality CPR in the moment, with the right guidance in their hand.

## Our Solution

CPR Coach stays with a bystander from the moment someone collapses until help arrives. It talks the rescuer through every decision the way a dispatcher would, watches their compressions through the iPhone camera, and speaks short corrections out loud so they never have to look away from the patient. The same live coach is available for practice, so users can build confidence long before an emergency.

Our target audience is everyday people who may witness a cardiac arrest and need immediate CPR guidance before emergency responders arrive.

CPR Coach is a novel multilingual AI-powered app created by **Lalith Bhima**, **Bhavika Bhima**, and **Yihan Duan**. In our demo, a bystander with no training uses CPR Coach to save a life, and our goal is for the app to help save millions more.

## Features

The app is organized into five tabs.

| Tab | What it does |
|-----|--------------|
| **Coach** | Live camera coaching. Blue skeletal keypoints track the rescuer's wrists, elbows, shoulders, and hips, and a green guidance box marks the center of the patient's chest. The app measures rate, depth, elbow lock, hand placement, and recoil, then speaks corrections such as pushing harder, recentering the hands, or holding a steady rhythm. Includes an immersive full-screen view. |
| **Emergency** | A hands-free voice assistant that walks the user through the CPR decision process. It asks whether the scene is safe, whether the person responds or is breathing, and whether the victim is an adult, child, or infant, then listens and decides the next step. Users can call emergency services in one tap. |
| **Learn** | Guided lessons on assessment, compressions, CPR quality, and AED use, read out loud and based on American Heart Association guidelines. |
| **Chat (ChatCPR)** | A multilingual AI assistant that answers CPR questions and can analyze live form. |
| **More** | Nearest hospitals, nearest AEDs, Progress reports, Calibration History, and Settings. |

**Additional highlights**

- **Multilingual system.** Every screen, spoken cue, and voice answer is localized across a wide range of languages, from the buttons to the voice that coaches each compression.
- **Local emergency number.** The app detects the user's country by GPS or device region and dials the correct number.
- **Worldwide AED locator.** AED stations are loaded from the bundled `WORLD.geojson` database, so the map works without an internet connection.
- **Progress tracking.** Every practice session is saved with live metric graphs, main corrections, and an AI session summary.
- **Depth calibration.** Users can calibrate compression depth to their own body.

---

# Technical Details

## System Architecture

CPR Coach processes every camera frame through four modalities and connects the results into the live experience on the Coach screen.

```text
 Camera frame (AVCapture / ARKit)
        │
        ▼
 ┌─────────────────────┐
 │ 1. Object detection │  YOLOv11 + Apple Vision human rectangles
 └─────────┬───────────┘  Finds every person in the scene
           ▼
 ┌─────────────────────┐
 │ 2. Pose estimation  │  MoveNet Thunder / Lightning + Apple Vision
 └─────────┬───────────┘  Body and hand keypoints, rescuer vs patient
           ▼
 ┌─────────────────────┐
 │ 3. Depth mapping    │  LiDAR scene depth (ARKit)
 └─────────┬───────────┘  Real 3D compression distance in cm
           ▼
 ┌─────────────────────┐
 │ 4. Analysis         │  Rate, depth, elbows, hands, recoil, errors
 └─────────┬───────────┘
           ▼
 Spoken coaching cue + on-screen overlay + saved session data
```

## AI Models and What They Do

CPR Coach is not one model. It is a set of AI models and algorithms that each handle one part of the problem, and the app only works because they run together in real time.

### Computer Vision Models

| Model | What it does in CPR Coach |
|-------|---------------------------|
| **YOLOv11** | Object detection. Finds the people in the frame so the app knows where the rescuer and patient are before looking at joints. Bundled as Core ML (`yolo11n.mlpackage`). |
| **MoveNet Thunder (TensorFlow Lite)** | The main pose model. Finds 17 body keypoints such as shoulders, elbows, wrists, and hips at a 256×256 input size, chosen for accuracy. Runs entirely on the phone. |
| **MoveNet Lightning INT8 (TensorFlow Lite)** | A smaller, faster quantized version of MoveNet used when speed matters more than precision. |
| **Apple Vision Body Pose** | Backup pose model. Takes over if MoveNet is unavailable, using the newest pose revision the device supports. |
| **Apple Vision Human Rectangles** | Draws a box around each person. The app matches each skeleton to its box and uses the box confidence to decide who is the rescuer. |
| **Apple Vision Hand Pose** | Tracks fingers and palms. Used to tell whether hands are stacked correctly, clenched into a fist, or only one hand is on the chest. |
| **Rescuer and Patient Classifier** | Our own scoring logic. Scores each person by posture, since the rescuer kneels upright and the patient lies flat, then locks onto the rescuer for the whole session. |
| **CPR Error Recognition Engine** | Our own 14-class recognizer that labels each moment of CPR as correct or as a specific mistake. See [CPR Error Recognition and Confidence](#cpr-error-recognition-and-confidence). |

### Depth and Signal Processing

| Method | What it does in CPR Coach |
|--------|---------------------------|
| **LiDAR Depth Mapping (ARKit)** | Measures the distance from the camera to the chest and the hands in 3D, so compression depth is measured in centimeters instead of guessed from flat video. Falls back to ARKit hit testing when scene depth is not available. |
| **One Euro Filter** | Smooths every joint separately to remove jitter without adding lag. It also holds a joint's last good position for a moment when it is hidden. |
| **Rate Fusion** | Combines four estimates of compressions per minute so no single method can fail on its own. See the weights below. |
| **Depth Calibration** | Lets each user calibrate depth to their own body size and camera position. |

Compression rate is a weighted blend of four methods:

| Method | Weight |
|--------|--------|
| Recent peak intervals | 0.38 |
| Discrete Fourier analysis (FFT) of wrist motion | 0.30 |
| Velocity zero crossings | 0.22 |
| Long window peak intervals | 0.10 |

This blend fixed an early bug where one method locked onto half the real speed and told fast rescuers to slow down.

### Language and Voice Models

| Model | What it does in CPR Coach |
|-------|---------------------------|
| **ChatGPT API (large language model)** | Powers ChatCPR, the live coaching conversation after the guided emergency steps, and the AI summary of each practice session. |
| **Retrieval Augmented Generation (RAG)** | Before the language model answers, the app searches a knowledge base built from American Heart Association guidance and gives the most relevant passages to the model, so answers stay grounded in real CPR guidelines. |
| **Apple NaturalLanguage Sentence Embeddings** | Turns each question and each knowledge passage into a vector on the phone, then finds the closest matches by cosine similarity. This is the search step of RAG. Falls back to keyword search if embeddings are unavailable. |
| **Apple Speech Recognition** | Converts what the rescuer says into text so they can answer emergency questions hands-free. A short pause automatically ends each answer. |
| **Speech Intent Matching** | Understands yes, no, unsure, ages, and emergency words in every supported language, including romanized spellings, to decide the next step of the emergency flow. |
| **Built-In Voice Engine** | An on-device CPR answer engine that classifies the question's intent and builds a reply from the knowledge base. It is always ready, with no download and no internet. |
| **Text to Speech (AVFoundation)** | Speaks every instruction and correction out loud in the user's language. |

We have also prepared a speech recognition fine-tuning dataset of **3,152** examples across all supported languages for a future on-device Whisper model. See [Roadmap for CPR Coach 2.0](#roadmap-for-cpr-coach-20).

### How the Models Work Together

1. YOLOv11 and Apple Vision find each person in the frame.
2. MoveNet finds the body keypoints, and Apple Vision Hand Pose finds the hands.
3. The Rescuer and Patient Classifier decides who is giving compressions and locks on.
4. The One Euro Filter steadies the blue skeleton, and the green chest box is anchored to the patient's torso just below the rescuer's arms.
5. LiDAR measures depth in centimeters while Rate Fusion measures compressions per minute.
6. The CPR Error Recognition Engine labels the current technique and checks that a mistake is consistent before acting on it.
7. The coaching engine picks the single most important correction, and Text to Speech says it out loud.
8. During the emergency flow, Speech Recognition and Speech Intent Matching listen to the rescuer, and ChatGPT with RAG answers open questions.
9. After practice, the ChatGPT API writes a session summary from the saved metrics.

## Scoring and Thresholds

All targets are based on the 2020 American Heart Association guidelines.

### AHA Coaching Targets

| Metric | Target | Notes |
|--------|--------|-------|
| Compression rate | 100 to 120 per minute | Ideal is 110 |
| Compression depth | 5 to 6 cm | Ideal is 5.5 cm |
| Elbow angle | 165 degrees or more | Relaxed to 158 degrees during the first setup window |
| Recoil ratio | 0.65 or more | Measures whether the chest comes all the way back up |
| Hand placement | Within 0.08 of chest center | Normalized screen distance from the sternum target |

### Compression Quality Score

Each moment of CPR earns up to 9 points.

| Check | Points |
|-------|--------|
| Hands centered on the chest | 2 |
| Elbows locked at 165 degrees or more | 2 |
| Rate between 100 and 120 per minute | 2 |
| Depth between 5 and 6 cm | 2 |
| Full chest recoil | 1 |

| Total points | Rating |
|--------------|--------|
| 8 to 9 | Excellent |
| 6 to 7 | Good |
| 3 to 5 | Needs Work |
| 1 to 2 | Poor |

### Pressure Score

A 0 to 100 score the app calculates during every session.

| Part | Max points | How it is scored |
|------|------------|------------------|
| Depth | 40 | Full 40 inside 5 to 6 cm. Loses 10 points per cm away from 5.5 cm. |
| Rate | 35 | Full 35 inside 100 to 120 per minute. Loses 0.8 points per compression away from 110. |
| Motion | 25 | Based on how far the wrists travel with each push. |

### CPR Error Recognition and Confidence

The error recognition engine scores 14 classes. Each class is only scored when the joints it needs are visible, so a close-up arm view still checks hands and arms while a full-body side view also checks posture.

| Class | Severity |
|-------|----------|
| Wrong position | 10 |
| Insufficient pressing | 9 |
| Single hand | 9 |
| Slow frequency | 8 |
| Excessive pressing | 8 |
| Bending arms | 7 |
| Standing | 7 |
| Jump pressing | 6 |
| Tilting arms | 5 |
| Squatting | 5 |
| Clenching hands | 4 |
| Overlapping hands | 3 |
| Random position pressing | 3 |
| Correct | 0 |

**How a mistake is confirmed**

1. A class must reach a confidence of **0.45** to be considered active.
2. The headline mistake is the active class with the highest severity × confidence.
3. A composite confidence score is calculated as **CS = objectness × temporal consistency**, where objectness is how confident the model is that it sees the rescuer, and temporal consistency is how often the same mistake appeared over the last **9** frames.
4. If **CS** is below **0.30**, the mistake is treated as a one-frame glitch and is not spoken. This keeps the coach from overloading the rescuer with false corrections.

### Coaching Margins

To avoid nagging, the app only speaks a rate or depth correction when the value is clearly outside the AHA range and the measurement is trustworthy.

| Correction | Fires when |
|------------|------------|
| Push faster | Rate below 95 per minute |
| Slow down | Rate above 125 per minute |
| Push harder | Depth below 4.6 cm |
| Ease up | Depth above 6.4 cm |
| Minimum confidence | Rate and depth confidence must be at least 0.55 |

### Python Prototype Thresholds

The original prototype in `live_movenet_cpr.py` uses simpler rules, checked in this priority order.

| Check | Threshold | Feedback |
|-------|-----------|----------|
| Keypoint visibility | Confidence below 0.3 on any shoulder, elbow, or wrist | Move body fully into camera view |
| Hand placement | Wrists more than 80 px from shoulder center | Move hands toward the center of the chest |
| Elbow angle | Below 150 degrees | Straighten your arms more |
| Rate too slow | Below 100 per minute | Compress faster |
| Rate too fast | Above 120 per minute | Slow down slightly |
| Depth | Wrist travel below 20 px | Push deeper |
| All good | None of the above | Good rhythm. Keep going |

### Evaluation

We evaluated form using 3D angle diagrams of the rescuer's joints. A lower theta indicates poorer CPR form and a higher theta indicates proper CPR form. We tested each version on a CPR manikin with each other as rescuers, across different rooms, lighting, and camera angles, and tuned the thresholds above based on where the app gave the wrong advice.

On live coaching session exports used for research figures:

| Metric | Result |
|--------|--------|
| MAPE (compression rate) | 2.93% |
| MSE (depth) | 0.31 cm² |
| Precision | 96.89% |
| Recall | 97.29% |
| F1 | 97.06 |

## Tech Stack

| Category | Tools |
|----------|-------|
| Languages | Swift (SwiftUI), Python |
| Development | Xcode, Visual Studio Code |
| Computer vision | YOLOv11 (Core ML), MoveNet Thunder and Lightning (TensorFlow Lite), Apple Vision |
| Depth | ARKit with LiDAR scene depth |
| AI | ChatGPT API, RAG with Apple NaturalLanguage embeddings |
| Voice | Apple Speech framework, AVFoundation text to speech |
| Maps and location | Apple Maps (MapKit), Core Location |
| Data | `WORLD.geojson` worldwide AED database, AHA knowledge base |
| Prototype | Python, OpenCV, NumPy, TensorFlow |

---

# Setup and Usage

## Requirements

| Item | Version |
|------|---------|
| Mac | macOS with Xcode 16 or later |
| iPhone | iOS 18.5 or later |
| LiDAR | Recommended (iPhone Pro models) for 3D depth. Other iPhones still get pose, rate, and placement coaching. |
| API key | ChatGPT API key for ChatCPR and AI session summaries |
| Python | 3.10 or later, only for the prototype and localization tools |

## Getting Started

### Step 1: Download the Project

Clone the repository or download it as a ZIP and unzip it.

```bash
git clone https://github.com/lalithbhima/CPRCoach.git
cd CPRCoach
```

### Step 2: Add Your API Key

1. Copy `Config/Secrets.example.swift` to `VisionCPRCoach/Config/Secrets.swift`.
2. Paste your **ChatGPT API** key between the quotes.
3. Never commit this file or any file that contains a real key.

The rest of the app — including camera coaching, the emergency flow, and the AED map — works without a key.

### Step 3: Open in Xcode

Double-click `VisionCPRCoach.xcodeproj`. Xcode will load the local TensorFlow Lite package from `LocalPackages/TensorFlowLite` automatically.

### Step 4: Set Up Signing

1. Select the **VisionCPRCoach** project in the left sidebar.
2. Open **Signing and Capabilities**.
3. Choose your Apple developer team. A free personal team works.
4. If Xcode reports a bundle identifier conflict, change `com.lalithbhima.VisionCPRCoach` to something unique.

### Step 5: Run on Your iPhone

1. Connect your iPhone with a cable and unlock it.
2. Turn on **Developer Mode** in Settings → Privacy and Security, if asked.
3. Select your iPhone as the run destination at the top of Xcode.
4. Press **Run** (`⌘R`).
5. Allow camera, microphone, speech recognition, and location access when prompted.

The camera, LiDAR, and microphone do not work in the iOS Simulator, so a real iPhone is required.

### Step 6: Your First Coaching Session

1. Choose your language on the welcome screen.
2. Open the **Coach** tab.
3. Place the phone on the floor or a stand about 1 to 2 meters away, looking at the patient or manikin from the side.
4. Make sure both the rescuer's arms and the patient's chest are in view.
5. Wait for the blue skeleton to lock onto you and the green box to appear on the chest.
6. Start compressions and follow the spoken corrections.
7. When you finish, open **More → Progress** to see your session report and AI summary.

To try the voice assistant, open the **Emergency** tab and answer each question out loud.

## Running the Python Prototype

Before building the iPhone app, we built the coaching logic in Python. `live_movenet_cpr.py` runs MoveNet Thunder on a webcam, tracks wrist motion to estimate compression rate, measures elbow angle and hand placement, and shows live feedback on screen. The iOS app ports this same logic into Swift.

```bash
python3 -m venv venv
source venv/bin/activate
pip install opencv-python numpy tensorflow
python live_movenet_cpr.py
```

Press `Q` to quit. The script needs `movenet_thunder.tflite` in the same folder, which is already included.

## Localization Tools

The `scripts/` folder holds the tools we used to build and check every language file.

| Script | Purpose |
|--------|---------|
| `build_all_localizations.py` | Checks that every language has every key from the English file |
| `sync_missing_locale_keys.py` | Translates any missing keys into each language |
| `generate_learn_and_keys.py` | Translates the Learn lessons into all languages |
| `add_nlp_tokens.py` | Adds speech intent words for the emergency flow |
| `expand_nlp_romanized.py` | Adds romanized spellings for languages with other scripts |
| `welcome_translations.py` | Applies welcome screen translations |

To check that all languages are complete:

```bash
python3 scripts/build_all_localizations.py
```

## Running Tests

In Xcode, press `⌘U` to run the unit tests in `VisionCPRCoachTests` and the UI tests in `VisionCPRCoachUITests`.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Blue skeleton does not appear | Move back so the rescuer's shoulders, elbows, and wrists are fully in view, and improve the lighting. |
| Skeleton jumps to the patient | Film from the side so the rescuer is kneeling upright and the patient is lying flat. |
| Depth always shows estimating | LiDAR needs an iPhone Pro model. On other phones, run depth calibration from the More tab. |
| ChatCPR says no API key | Check that `VisionCPRCoach/Config/Secrets.swift` exists and contains your ChatGPT API key. |
| Voice assistant does not hear you | Allow microphone and speech recognition access in Settings, then restart the app. |
| Build fails on signing | Select your developer team and use a unique bundle identifier. |
| YOLOv11 pill missing | Confirm `Resources/yolo11n.mlpackage` is present and rebuild so Xcode compiles the Core ML model. |

## Folder Structure

```text
CPRCoach/
├── VisionCPRCoach/                    # iOS app source (SwiftUI)
│   ├── VisionCPRCoachApp.swift        # App entry point
│   ├── MainTabView.swift              # Coach, Emergency, Learn, Chat, More tabs
│   │
│   ├── Coaching and computer vision
│   │   ├── CameraViewModel.swift              # Frame pipeline and live state
│   │   ├── YOLOv11ObjectDetector.swift        # YOLOv11 Core ML object cues
│   │   ├── MoveNetPoseEstimator.swift         # MoveNet pose model on device
│   │   ├── MultiPersonPoseAnalyzer.swift      # Rescuer and patient separation
│   │   ├── PoseTrackingFilter.swift           # One Euro smoothing and rescuer lock
│   │   ├── CPRChestTargetEstimator.swift      # Green chest target box
│   │   ├── CompressionDepth3DEstimator.swift  # LiDAR compression depth
│   │   ├── CPRMetricsEngine.swift             # Rate fusion, depth, recoil, scores
│   │   ├── CPRActionRecognitionEngine.swift   # 14-class CPR error recognition
│   │   ├── RealTimeCPRResponseEngine.swift    # Spoken coaching cues
│   │   └── CPRGuidelines.swift                # AHA targets and thresholds
│   │
│   ├── Emergency and voice
│   │   ├── EmergencyGuidedFlowEngine.swift    # Dispatcher-style decision flow
│   │   ├── SpeechRecognitionManager.swift     # Hands-free listening
│   │   ├── BuiltInCPRVoiceEngine.swift        # On-device CPR answers
│   │   ├── VoiceCoach.swift                   # Text to speech
│   │   ├── EmergencyNumberService.swift       # Local emergency number
│   │   ├── HospitalLocatorService.swift       # Nearest hospitals
│   │   └── AEDGeoJSONStore.swift              # Worldwide AED lookup
│   │
│   ├── AI assistant
│   │   ├── AIAssistantView.swift              # ChatCPR screen
│   │   ├── RAGRetriever.swift                 # Embedding search for RAG
│   │   └── CPRSessionAnalysisService.swift    # AI session summaries
│   │
│   ├── Progress and learning
│   │   ├── CPRProgressView.swift              # Session history and graphs
│   │   ├── CPRSessionDetailView.swift         # Session report
│   │   └── TrainingView.swift                 # Learn tab
│   │
│   ├── Resources/
│   │   ├── yolo11n.mlpackage                  # YOLOv11 object detection model
│   │   ├── WORLD.geojson                      # Worldwide AED database
│   │   ├── cpr_knowledge.json                 # AHA knowledge base for RAG
│   │   ├── cv_reference_metrics.json          # Vision validation targets
│   │   ├── movenet_thunder.tflite             # Pose model (accuracy)
│   │   ├── movenet_lightning_int8.tflite      # Pose model (speed)
│   │   ├── languages.json                     # Supported languages
│   │   ├── Localizations/                     # Language files
│   │   ├── Learn/                             # Learn tab lessons
│   │   └── TrainingSamples/                   # Speech fine-tuning dataset
│   │
│   ├── assests/                               # Logo assets
│   └── Assets.xcassets/                       # App icon and images
│
├── VisionCPRCoach.xcodeproj/          # Xcode project
├── VisionCPRCoachTests/               # Unit tests
├── VisionCPRCoachUITests/             # UI tests
├── LocalPackages/TensorFlowLite/      # TensorFlow Lite Swift package
├── Config/                            # API key template
├── scripts/                           # Localization and translation tools
├── live_movenet_cpr.py                # Python prototype of the coaching logic
└── movenet_thunder.tflite             # Model used by the Python prototype
```

The groupings under `VisionCPRCoach/` are for readability. In the project, these Swift files sit directly inside `VisionCPRCoach/`.

---

# Project Information

## How We Used AI in Development

We used ChatGPT, Cursor, and Claude to brainstorm and draft early versions of features, explain errors, help us debug, and suggest test cases. Our team designed every feature, coded the app, wrote the emergency conversation flow, tested each version, and rewrote or removed any AI suggestion that did not hold up for CPR. Nothing stayed in the app unless one of us understood it and approved it.

## Privacy and Permissions

| Permission | Why it is needed |
|------------|------------------|
| Camera | Analyze hand placement, compression rate, and depth in real time |
| Microphone | Voice-guided emergency questions and AI coaching |
| Speech recognition | Answer emergency questions hands-free |
| Location | Find the local emergency number, nearest hospitals, and nearest AEDs |

Camera frames are processed on the phone and are not uploaded. Practice sessions are stored on the device.

## Roadmap for CPR Coach 2.0

- **Full offline support.** Move the AI assistant, session summaries, and speech recognition onto the device, including a Whisper model fine-tuned on our multilingual dataset, so every feature works with no network.
- **Whole scene understanding.** Recognize when more helpers arrive and coach the group like a team leader, including switching compressors every two minutes and sending someone for an AED.
- **Accessibility.** Vibration at the correct compression rhythm and large visual cues for deaf and hard of hearing rescuers, a voice-only experience for blind and low vision users, and guidance for people with limited mobility to direct a nearby bystander.
- **American Heart Association partnership.** Validate our coaching with certified instructors and bring CPR Coach into schools, churches, and community centers.

## Disclaimer

CPR Coach is a guidance and training tool. It is not a medical device and does not replace professional medical care or certified CPR training. In an emergency, always call your local emergency number first.

## Contact and Links

| Item | Detail |
|------|--------|
| Creators | Lalith Bhima, Bhavika Bhima, Yihan Duan |
| Demo video | [`docs/media/CPR_Coach_Demo.mp4`](docs/media/CPR_Coach_Demo.mp4) |
| GitHub | [github.com/lalithbhima/CPRCoach](https://github.com/lalithbhima/CPRCoach) |
| Congressional App Challenge | Add your district submission / video link here |

---

<p align="center">
  <strong>CPR Coach</strong> — practice with vision. Act with confidence. Call for help first.
</p>
