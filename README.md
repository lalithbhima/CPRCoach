# CPR Coach

<p align="center">
  <img src="docs/assets/CPRCoachLogo.png" alt="CPR Coach logo" width="220"/>
</p>

<p align="center">
  <strong>Vision CPR Coach</strong> — a multilingual, on-device computer-vision iPhone app that trains people for high-quality CPR and guides bystanders through real emergencies with live coaching, voice AI, and nearest-help tools.
</p>

<p align="center">
  <em>Training and decision support only. Not a medical device. In a real emergency, call 911 (or your local emergency number) immediately.</em>
</p>

<p align="center">
  <strong>Congressional App Challenge</strong> · Creators: <strong>Lalithendra Reddy Bhima</strong> &amp; <strong>Bhavika Bhima</strong> · Coach: <strong>Madhava Bhima</strong>
</p>

---

> **Demo Video:** full product walkthrough (Live Coach, Emergency Voice AI, Learn, ChatCPR, vision stack, and evaluation narrative)

https://github.com/user-attachments/assets/placeholder

<video src="docs/media/CPR_Coach_Demo.mp4" controls width="720"></video>

**[Watch CPR Coach Demo (`docs/media/CPR_Coach_Demo.mp4`)](docs/media/CPR_Coach_Demo.mp4)**

**Quick Stats**

| | |
|---|---|
| 🎯 **MAPE (compression rate)** | **2.93%** on 61 live coaching sessions / 3,999 usable frames |
| 📐 **MSE (depth)** | **0.31 cm²** with LiDAR–pose fusion |
| ✅ **Precision / Recall / F1** | **96.89% / 97.29% / 97.06** coaching reliability |
| 🛰️ **LiDAR depth error cut** | **~77%** vs pose-only (MSE 1.97 vs 8.63 cm²) |
| 🌍 **Languages** | **45** UI + speech locales |
| 💓 **AED stations on device** | **166,925** (bundled worldwide GeoJSON) |
| 🧠 **Vision modalities** | **4** — YOLOv11 · MoveNet · Apple Vision · LiDAR |
| ⚡ **Design latency** | **&lt;400 ms** end-to-end coaching loop |

---

## Table of Contents

- [The Problem](#the-problem)
- [Our Solution](#our-solution)
  - [Key Features](#key-features)
  - [Who It Is For](#who-it-is-for)
- [How It Works](#how-it-works)
  - [Architecture](#architecture)
  - [End-to-End Coaching Pipeline](#end-to-end-coaching-pipeline)
  - [Four Vision Modalities](#four-vision-modalities)
  - [Technical Highlights: Rescuer–Patient Separation &amp; Depth Fusion](#technical-highlights-rescuerpatient-separation--depth-fusion)
  - [Metrics Math (Rate, Depth, Elbows, Hands, Recoil)](#metrics-math-rate-depth-elbows-hands-recoil)
  - [Action Recognition (14 Classes)](#action-recognition-14-classes)
  - [AI Models, RAG &amp; ChatGPT API](#ai-models-rag--chatgpt-api)
  - [Emergency Voice Flow](#emergency-voice-flow)
- [Performance Metrics](#performance-metrics)
- [Research Impact (MTFC / Public Health)](#research-impact-mtfc--public-health)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [1. Clone and Open](#1-clone-and-open)
  - [2. Configure the ChatGPT API Key](#2-configure-the-chatgpt-api-key)
  - [3. Build and Run on a Device](#3-build-and-run-on-a-device)
  - [4. First-Run Walkthrough](#4-first-run-walkthrough)
  - [5. Practice Session Checklist](#5-practice-session-checklist)
- [Project Structure](#project-structure)
- [Scripts &amp; Research Tooling](#scripts--research-tooling)
- [App Inventor / Appathon Frontend](#app-inventor--appathon-frontend)
- [Roadmap](#roadmap)
- [Troubleshooting](#troubleshooting)
- [Lessons Learned (Hard Problems We Solved)](#lessons-learned-hard-problems-we-solved)
- [Congressional App Challenge Notes](#congressional-app-challenge-notes)
- [Contributing](#contributing)
- [Acknowledgments](#acknowledgments)
- [License](#license)
- [Contacts &amp; Links](#contacts--links)
- [Citation](#citation)

---

## The Problem

Cardiac arrest can happen anywhere, with no warning. Nearby people often have only seconds to act, and hesitation can be the difference between life and death.

| Scope | Approximate burden |
|------|---------------------|
| California | ~65,000 cardiac arrests per year (pitch); CARES-scaled full-state ~28,800 EMS-treated cases |
| United States | &gt;400,000 public narrative; **263,711** EMS-treated non-traumatic OHCA (CARES 2024) |
| Global | ~5 million per year |

Public-health and CARES-aligned facts that motivate the product:

- Performing bystander CPR can roughly **triple** survival odds versus no CPR.
- About **90%** of out-of-hospital cardiac arrests do not survive in the public narrative; CARES 2024 reports **10.5%** survival to discharge and **8.2%** favorable neurologic outcome among EMS-treated cases.
- Fewer than **3%** of people are trained to perform CPR in the narrative we use for outreach; adult bystander CPR is started in only **~41.7%** of CARES cases.
- Every minute without CPR can reduce survival by roughly **7–10%**.
- Survival with bystander CPR **13.0%** vs **7.6%** without (CARES 2024).
- Public AED use remains low (**~9.9%** in California CARES 2024).

Most of the time, the person who can save a life is not a clinician in the room — it is a bystander who needs clear, calm, high-quality guidance **before** EMS arrives.

---

## Our Solution

**CPR Coach (Vision CPR Coach)** is a novel multilingual AI-powered iOS application that:

1. **Trains** people ahead of time with live camera coaching (rate, depth, hands, elbows, recoil).
2. **Guides** them during a suspected emergency with a voice assistant that walks through safety checks, EMS activation, AED retrieval, and compressions.
3. **Educates** with structured Learn modules and ChatCPR (RAG-grounded answers via the ChatGPT API).
4. **Locates** help via Apple Maps hospitals and a bundled worldwide AED database (**166,925** stations).

The product is built as training and decision support — never as a replacement for certified training or professional care.

### Key Features

- **Live Coach** — real-time joint tracking (wrists, elbows, shoulders, hips), patient chest guidance box, CPM / depth / elbow / placement / recoil metrics, spoken cues, optional depth calibration, immersive full-screen mode, status pills (Live · AI Detection · AI Model · YOLOv11 · LiDAR Depth).
- **Four-modality vision** — YOLOv11n scene/person cues, MoveNet Thunder keypoints, Apple Vision pose/rects/hands, LiDAR/ARKit metric depth on Pro devices.
- **Emergency Voice AI** — dispatcher-style dialogue (scene safety → responsiveness → breathing → call EMS → AED → CPR → recovery) with Apple Speech STT + TTS and ChatGPT API turns grounded by on-device RAG.
- **Learn** — four professional modules (Primary Assessment, Compressions, CPR Quality/Physiology/Technology, AED/EMS/Post-Arrest) with voice read-along.
- **ChatCPR** — multilingual Q&amp;A with RAG (`k = 4`), suggestion chips, optional “Analyze my form” using live metrics.
- **Hospitals &amp; AEDs** — MapKit nearby ERs; distance-ranked AEDs from on-device GeoJSON.
- **Progress &amp; Calibration** — session scores, charts, export/share, personalized depth scale history.
- **Multilingual** — **45** languages for UI strings and speech locales, including Emergency yes/no NLP tokens.

### Who It Is For

- Everyday people who may witness cardiac arrest and need guidance before EMS arrives.
- Students and families practicing on a manikin or training setup.
- Schools, clubs, and community programs that want a practice companion beside formal certification.
- Researchers studying multimodal CPR feedback (vision + voice + RAG).

**Not for:** replacing licensed medical care, diagnosing patients, or delaying a call to emergency services.

---

## How It Works

### Architecture

```text
iPhone (Camera + optional LiDAR) + Mic + Speakers
  │
  ├─ Camera / ARKit (AVCapture or LiDAR ARSession)
  │   ├─ RGB frames → MultiPersonPoseAnalyzer
  │   └─ sceneDepth (Pro) → CompressionDepth3DEstimator
  │
  ├─ Vision stack (on-device)
  │   ├─ YOLOv11n Core ML (VNCoreMLRequest)     — person / scene cues
  │   ├─ MoveNet Thunder TFLite (256×256)         — primary keypoints
  │   ├─ Apple Vision body pose / human rects / hands
  │   └─ PoseTrackingFilter                       — temporal lock-on
  │
  ├─ Metrics & coaching
  │   ├─ CPRMetricsEngine   — CPM · depth · elbows · hands · recoil
  │   ├─ CPRActionRecognitionEngine — 14 error/correct classes
  │   └─ RealTimeCPRResponseEngine + VoiceCoach (TTS)
  │
  ├─ Language & knowledge
  │   ├─ LanguageManager (45 locales)
  │   ├─ RAGRetriever (NLEmbedding + keyword fallback)
  │   └─ ChatGPT API (ChatCPR + Emergency LLM turns)
  │
  └─ Maps / persistence
      ├─ MapKit hospitals · WORLD.geojson AEDs (166,925)
      └─ Progress / calibration / session export (on-device)
```

| Layer | Responsibility | Primary tech |
|------|----------------|--------------|
| **UI** | Tabs, immersive coach, glass/bubble design | SwiftUI |
| **Camera / AR** | Preview + LiDAR scene depth when available | AVFoundation, ARKit |
| **Vision** | Keypoints, detection, multi-person logic | MoveNet Thunder (TFLite), Apple Vision, YOLOv11n (Core ML) |
| **Metrics** | CPM, depth, placement, recoil, quality | Custom Swift + peak / zero-cross / FFT fusion |
| **Voice** | STT / TTS, emergency dialogue, live coach phrases | Apple Speech, AVSpeechSynthesizer |
| **Language model** | ChatCPR + emergency conversational answers | **ChatGPT API** + on-device RAG |
| **Maps / AED** | Hospitals and AED stations | MapKit / Apple Maps, `WORLD.geojson` |
| **Persistence** | Sessions, calibration, language prefs | App sandbox / UserDefaults |
| **Research / offline** | Figures, MAPE/MSE, hyperparameter sweeps | Python (NumPy, Matplotlib, MoveNet scripts) |

**Main tabs:** Coach · Emergency · Learn · ChatCPR · More (Hospitals, AEDs, Progress, Calibration, Settings).

### End-to-End Coaching Pipeline

1. **Capture** — Camera frame (`AVCapture`) or ARKit camera frame on LiDAR devices (`LiDARDepthSession`).
2. **Detect (YOLOv11)** — Core ML `yolo11n` via `VNCoreMLRequest` yields person / scene boxes (confidence ≥ 0.30) for CPR-relevant labels (`person`, `bed`, `couch`, gear, etc.).
3. **Pose (MoveNet)** — Thunder TFLite estimates full-body keypoints; primary path when the model is loaded.
4. **Fallback / complement (Apple Vision)** — body pose if MoveNet is unavailable; always run human rectangles + hand pose for scene and wrist refinement.
5. **Depth (LiDAR)** — when supported, ARKit `sceneDepth` estimates 3D compression amplitude; otherwise motion amplitude + **Calibrate**.
6. **Filter** — `PoseTrackingFilter` stabilizes joints and keeps a sticky rescuer / patient lock.
7. **Measure** — `CPRMetricsEngine` computes rate, depth, elbows, placement, recoil, quality / confidence.
8. **Recognize actions** — 14-class taxonomy surfaces the most urgent form error when joints support it.
9. **Coach** — guideline-gated short TTS cues + UI metrics grid; confidence gates suppress noisy talk.
10. **Assist** — Emergency / ChatCPR retrieve top-k knowledge chunks (RAG), call the **ChatGPT API** with live metrics when relevant.
11. **Locate** — Hospitals / AEDs via location + MapKit + GeoJSON.
12. **Review** — Progress stores session scores for charts, export, and calibration history.

### Four Vision Modalities

| Modality | Asset / API | Role |
|----------|-------------|------|
| **YOLOv11n** | `Resources/yolo11n.mlpackage` (~2.8 MB; NMS pipeline; COCO classes) | Object / scene / person cues; strengthens lying-patient boxes when Vision human-rects miss |
| **MoveNet Thunder** | `movenet_thunder.tflite` (~12 MB, 256×256) | Primary full-body keypoints for the live skeleton overlay |
| **Apple Vision** | `VNDetectHumanBodyPoseRequest`, human rectangles, hand pose | Pose fallback; person boxes; hand-refined wrists |
| **LiDAR / ARKit** | `LiDARDepthSession` + `CompressionDepth3DEstimator` | Metric 3D compression depth on Pro / Max devices |

Status pills in Coach UI: **AI Model** (MoveNet loaded) · **YOLOv11** (Core ML loaded) · **LiDAR Depth** (active scene depth) · detection quality %.

### Technical Highlights: Rescuer–Patient Separation &amp; Depth Fusion

**Problem we hit in early builds:** CPR always involves two bodies pressed together. Naive pose models jumped between rescuer and patient; the chest box bounced with the wrists.

**What we ship now:**

1. **Score posture** — rescuer = upright / kneeling with arm confidence; patient = horizontal torso (shoulder–hip geometry or horizontal person box from Vision / YOLO).
2. **Sticky lock** — `PoseTrackingFilter` holds the rescuer identity across frames instead of re-picking every tick.
3. **Chest target** — guidance box anchored to patient torso anatomy (or horizontal body box) **below** the compressing hands, not glued to the wrists.
4. **Occlusion hold** — joints remember last good positions briefly when side-camera wrists disappear behind the chest.
5. **Depth fusion** — when LiDAR and camera amplitudes exist:

```text
depth_cm ≈ 0.72 × lidarDepthCm + 0.28 × cameraDepth
```

Camera-only torso blend (no LiDAR): `0.62 × cameraDepth + 0.38 × torsoDepth`.

6. **Coaching hysteresis** — a mistake must persist across many frames before TTS fires, reducing cognitive overload.

### Metrics Math (Rate, Depth, Elbows, Hands, Recoil)

AHA-aligned targets encoded in `CPRGuidelines` / `cv_reference_metrics.json` (the LLM does **not** invent clinical thresholds):

| Quantity | Target / rule |
|----------|----------------|
| Compression rate | **100–120 CPM** (ideal ~110); coach below ~95 / above ~125 |
| Compression depth | **5–6 cm** adults (ideal ~5.5); coach below ~4.6 / above ~6.4 |
| Elbow angle | Prefer near-locked arms (**≥165°** UI / guideline floor) |
| Hand placement | Centered within tolerance **0.08** (normalized); labels: Centered, Too Far Left/Right, Too High/Low |
| Recoil | Full if upward ratio ≥ **0.65**; else Incomplete |
| Pose / YOLO confidence gate | ~**0.30** before trusting detections for coaching |

**CPM fusion** (`estimateCPM`) blends four estimators, then applies `rateMeasurementScale` (1.04):

| Estimator | Weight |
|-----------|--------|
| Recent peak intervals | 0.38 |
| Zero-crossings | 0.22 |
| FFT on wrist vertical motion | 0.30 |
| Peak count | 0.10 |

Cap at 150 CPM. Depth uses `depthMeasurementScale` (1.08) after fusion / calibration.

### Action Recognition (14 Classes)

`CPRErrorAction` taxonomy (severity-ranked for the headline cue):

`correct` · `overlapHands` · `clenchingHands` · `singleHand` · `bendingArms` · `tiltingArms` · `jumpPressing` · `squatting` · `standing` · `wrongPosition` · `insufficientPressing` · `slowFrequency` · `excessivePressing` · `randomPositionPressing`

A class is only asserted when the joints / hands it needs are visible.

### AI Models, RAG &amp; ChatGPT API

| Component | Technology | Runs on |
|-----------|------------|---------|
| Object / scene cues | YOLOv11n Core ML (`VNCoreMLRequest`) | Device |
| Pose estimation | MoveNet Thunder TFLite | Device |
| Pose / humans / hands | Apple Vision | Device |
| Depth | ARKit scene depth / LiDAR | Device (Pro) |
| Speech recognition | Apple Speech | Device |
| Text-to-speech | AVSpeechSynthesizer | Device |
| Knowledge retrieval | `RAGRetriever` + `NLEmbedding.sentenceEmbedding` | Device |
| Conversational answers | **ChatGPT API** (chat completions) | Cloud |
| Maps | MapKit / Apple Maps | Device + Apple services |
| AED index | Bundled `WORLD.geojson` | Device |

**Production LLM / RAG hyperparameters** (tuned via sweep; grounding/alignment ≈ 0.97):

| Parameter | Value | Why |
|-----------|-------|-----|
| Temperature | **0.35** | Stable, coach-like answers |
| Max tokens (live Emergency) | **180** | Short spoken replies |
| Max tokens (ChatCPR) | up to **600** | Longer educational answers |
| RAG top-k | **4** | Grounding chunks per turn |
| Pose / detection gate | **~0.30** | Suppress weak coaching |

**Knowledge base:** `Resources/cpr_knowledge.json` (**20** chunks at runtime; builder: `scripts/prepare_cpr_knowledge.py`). Fallback hardcoded chunks in `CPRKnowledgeBase`. System prompts require calling EMS in true emergencies, forbid fabricated drug doses / diagnoses, and keep answers educational.

**ChatGPT API configuration** (see [Getting Started](#2-configure-the-chatgpt-api-key)): the app loads a local secret file at build/runtime. Without a key, on-device coaching, Learn, maps, and AEDs still work; ChatCPR / LLM emergency turns are disabled.

### Emergency Voice Flow

`EmergencyGuidedFlowEngine` steps (one clear question at a time):

```text
confirmEmergency → victimAge → sceneSafe → checkResponsive → checkBreathing
  → call911 → confirm911 → getAED → startCPR → activeCoaching → recoveryMonitor
```

Plus a `notEmergency` exit. Local emergency numbers are region-aware; quick actions open call / hospital / AED. Conversation log + summary when the voice session ends.

---

## Performance Metrics

Evaluated on **device-exported** live coaching sessions (idle / unknown frames filtered; shallow-depth calibration adjustments applied in analysis scripts).

| Metric | Result | Notes |
|--------|--------|-------|
| **Sessions / usable frames** | **61 / 3,999** | Live coach exports |
| **MAPE (compression rate)** | **2.93%** | Mean absolute % error vs session references |
| **MSE (depth)** | **0.31 cm²** | Fused / calibrated estimation |
| **Precision** | **96.89%** | Coaching feedback reliability |
| **Recall** | **97.29%** | Coverage of relevant coaching events |
| **F1** | **97.06** | Harmonic mean |
| **LiDAR fusion MSE** | **1.969** | vs pose-only **8.627** / SfM **9.02** (~**77%** reduction) |
| **Mean calibrated depth** | **2.766 cm** | Calibration baseline statistic from eval set |
| **End-to-end latency goal** | **&lt;400 ms** | Capture → metrics → cue (MTFC design target) |

Source CSV: `Research Paper/validation_data/cpr_coach_statistics_summary.csv`  
Figures / sweeps: `Research Paper/graphs/`, `validation_data/hyperparameter_sweep_results.csv`

Paper-subset reference fields also live in `VisionCPRCoach/Resources/cv_reference_metrics.json` (e.g. historical paper MAPE **1.82%**, latency **28 ms** on a narrower subset). For competition “live coach” claims, prefer the **2.93% / 0.31 / 96.89…** table above.

---

## Research Impact (MTFC / Public Health)

Actuarial and public-health modeling for the Modeling the Future Challenge / Save a Million Lives context lives under `Research Paper/MTFC_2027/`.

**Illustrative base-case outputs (see report for assumptions):**

| Projection | Value |
|------------|-------|
| Year-10 lives saved (base) | **546** |
| 10-year cumulative | **2,956** |
| Monte Carlo median (N=10,000) | **3,062** (P5 **1,297**, P95 **6,106**) |
| Social value (VSL ~$13.7M) | ~**$41.9B** illustrative |
| SaML ladder combined | ~**986,000** expected lives saved (multi-intervention ladder) |

These are **research projections**, not clinical guarantees. Full narrative: `Research Paper/MTFC_2027/CPR_Coach_MTFC_Project_Report.md` (and PDF/DOCX siblings).

---

## Getting Started

### Prerequisites

| Component | Requirement |
|-----------|-------------|
| Mac | macOS with a recent **Xcode** (project destinations include **iOS 18.5** simulators) |
| iPhone | Physical device strongly recommended (camera + mic); **LiDAR** (12 Pro / 13 Pro / 14 Pro / 15 Pro / 16 Pro family) unlocks full depth path |
| Account | Apple Developer team for device signing |
| ChatGPT API | Optional for ChatCPR / LLM emergency turns; on-device coach works without it |
| Python 3 | Optional, for research scripts and localization tooling |

Simulator note: UI builds, but live camera coaching and LiDAR require a **physical iPhone**.

### 1. Clone and Open

```bash
git clone https://github.com/lalithbhima/CPRCoach.git
cd CPRCoach
open VisionCPRCoach.xcodeproj
```

If you are working from the Congressional App Challenge wrap folder:

```bash
cd APPChallenge/CPRCoach   # or the nested mirror you use
open VisionCPRCoach.xcodeproj
```

Swift sources under `VisionCPRCoach/` are included via Xcode’s synchronized root group — new `.swift` files and `Resources/yolo11n.mlpackage` are picked up automatically.

### 2. Configure the ChatGPT API Key

**Never commit real keys.** Secrets are gitignored.

Create a local secret file the app can load (placeholder shape):

```json
{
  "CHATGPT_API_KEY": "sk-proj-YOUR_KEY_HERE"
}
```

or TypeScript-style config used by the build sync script:

```ts
export const CHATGPT_API_KEY = "sk-proj-YOUR_KEY_HERE";
```

**Where to put it (pick the path your tree uses):**

- `VisionCPRCoach/Config/secret.ts` (build copies into the bundle), and/or  
- `VisionCPRCoach/Resources/*_secret.json` (example file ships empty), and/or  
- `Config/Secrets.swift` generated from `Secrets.example.swift`

**Get a key:** [OpenAI API keys](https://platform.openai.com/api-keys) (ChatGPT / Chat Completions API).

Without a key, Live Coach, Learn, Hospitals, AEDs, Progress, and multilingual UI still run. ChatCPR and LLM-backed emergency answers stay disabled.

### 3. Build and Run on a Device

1. In Xcode, select the **VisionCPRCoach** target.
2. **Signing &amp; Capabilities** → choose your Team; update the bundle ID if needed (`com.lalithbhima.VisionCPRCoach` by default).
3. Connect an iPhone → select it as the run destination.
4. Build and run (**⌘R**).
5. Grant **Camera**, **Microphone**, **Speech Recognition**, and **Location** when prompted.

First build may compile Core ML (`yolo11n`) and fetch the local TensorFlow Lite package under `LocalPackages/TensorFlowLite`.

### 4. First-Run Walkthrough

1. Choose language (45 options).  
2. Complete Welcome.  
3. Open **Coach** → **Start Coaching** → position the phone so the rescuer and manikin / patient region are visible.  
4. Watch for status pills: Live, AI Detection %, AI Model, YOLOv11, LiDAR Depth (on Pro).  
5. Optionally **Calibrate** after a set of good compressions.  
6. Explore **Emergency** (voice flow), **Learn**, **ChatCPR**, **More → Hospitals / AEDs / Progress**.

### 5. Practice Session Checklist

**Live Coach**

1. Place the phone on a stable stand ~1–2 m from the side of the rescuer.  
2. Start coaching; confirm the blue skeleton locks on the **rescuer** and the green box stays on the **chest**.  
3. Compress at ~110 CPM, ~5–6 cm; listen for rate / depth / placement cues.  
4. Stop → check Progress for score breakdown.

**Emergency Voice AI**

1. Start Emergency → answer scene / responsiveness / breathing prompts out loud.  
2. Confirm EMS call step; try Find Hospital / Find AED.  
3. Enter active coaching and verify TTS cues remain short.

**ChatCPR**

1. Ask “How deep should I press?” — answer should cite guideline bands and remind to call EMS in a real emergency.  
2. Use “Analyze my form” during / after a coach session if metrics are live.

**Offline sanity**

1. Enable Airplane Mode.  
2. Confirm Coach + AED map (bundled GeoJSON) still work.  
3. ChatGPT-backed ChatCPR should fail gracefully without network.

---

## Project Structure

```text
CPRCoach/                             # GitHub repository root
├── README.md                         # This document
├── docs/
│   ├── assets/CPRCoachLogo.png
│   └── media/CPR_Coach_Demo.mp4
├── CAC_Responses.md                  # Official Congressional App Challenge responses
├── VisionCPRCoach/                   # SwiftUI app sources + Resources
│   ├── YOLOv11ObjectDetector.swift
│   ├── MoveNetPoseEstimator.swift
│   ├── MultiPersonPoseAnalyzer.swift
│   ├── CameraViewModel.swift
│   ├── CPRMetricsEngine.swift
│   ├── CPRActionRecognitionEngine.swift
│   ├── EmergencyGuidedFlowEngine.swift
│   ├── LiDARDepthSession.swift
│   ├── CoachView.swift / ImmersiveCoachView.swift
│   └── Resources/
│       ├── yolo11n.mlpackage
│       ├── movenet_thunder.tflite
│       ├── movenet_lightning_int8.tflite
│       ├── WORLD.geojson             # 166,925 AED features
│       ├── cpr_knowledge.json
│       ├── cv_reference_metrics.json
│       └── Localizations/            # 45 locale JSON files
├── Config/                           # Secrets templates (gitignored keys)
├── LocalPackages/TensorFlowLite
├── scripts/                          # Localization + model helpers
├── live_movenet_cpr.py               # Python prototype / reference
└── VisionCPRCoach.xcodeproj
```

Challenge wrap (demo, research paper, App Inventor) may also live in the APPChallenge folder used for submission packaging.

---

## Scripts &amp; Research Tooling

### Challenge / knowledge (`APPChallenge/scripts/`)

| Script | Purpose |
|--------|---------|
| `prepare_cpr_knowledge.py` | PDF / sources → ~400-char chunks → `cpr_knowledge.json` |
| `download_cpr_training_samples.sh` | Bootstrap TrainingSamples imagery |

### App localization &amp; models (`CPRCoach/scripts/`)

| Script | Purpose |
|--------|---------|
| `download_movenet.sh` | Fetch / copy MoveNet Thunder TFLite |
| `build_all_localizations.py` | Validate every locale has all `en.json` keys |
| `sync_missing_locale_keys.py` | Fill missing keys |
| `generate_learn_and_keys.py` / `embed_learn_keys.py` | Learn module translation pipeline |
| `add_nlp_tokens.py` / `apply_nlp_locales.py` / `expand_nlp_romanized.py` | Emergency STT yes/no tokens |
| `welcome_translations.py` | Welcome strings across 45 locales |

### Evaluation (`Research Paper/`)

| Artifact | Purpose |
|----------|---------|
| `validation_data/cpr_coach_statistics_summary.csv` | MAPE / MSE / P / R / F1 / LiDAR vs pose-only |
| `validation_data/hyperparameter_sweep_results.csv` | Temperature / tokens / RAG-k / confidence winners |
| `generate_cpr_statistics_figures.py` | Pitch / paper figures |
| `generate_hyperparameter_tuning_graphs.py` | Sweep plots |
| `MTFC_2027/run_mortality_model.py` | Actuarial projection |

---

## App Inventor / Appathon Frontend

For MIT App Inventor / Appathon-style demos (separate from the production SwiftUI app):

- Packages under `CPRCoach-AppInventor/` (e.g. `CPRCoach_Frontend_Appathon.aia`)
- Builder scripts `build_*_aia.py` regenerate importable `.aia` ZIPs mirroring the iOS tab structure

Import the `.aia` in MIT App Inventor; this is a **frontend exploration**, not the live four-modality coach.

---

## Roadmap

**Completed**

- [x] Live Coach with multi-joint tracking and spoken cues  
- [x] Four-modality vision path (YOLOv11, MoveNet, Apple Vision, LiDAR)  
- [x] Rescuer–patient separation, chest-box anchoring, temporal pose filter  
- [x] CPM fusion (peaks + zero-cross + FFT) and LiDAR depth blend (72/28)  
- [x] 14-class action recognition taxonomy  
- [x] Emergency Voice AI guided flow + call / hospital / AED actions  
- [x] Learn modules with voice read-along  
- [x] ChatCPR with RAG + ChatGPT API  
- [x] Hospitals (Apple Maps) and worldwide AED GeoJSON (166,925)  
- [x] Progress, session export/share, calibration history  
- [x] Multilingual UI / speech (45 languages)  
- [x] Hyperparameter tuning for live LLM + pose gates  
- [x] Research metrics (MAPE, MSE, precision / recall / F1) and MTFC report  
- [x] MIT App Inventor frontend packaging for competition demos  

**In progress / near-term**

- [ ] Stronger fully-offline LLM / RAG path when the network is unavailable  
- [ ] Richer multi-rescuer scene understanding (role assignment, 2-minute switch cues)  
- [ ] Accessibility: haptic compression metronome, large visual-only mode, voice-only blind path  

**Future**

- [ ] Instructor / AHA-aligned validation studies at community scale  
- [ ] Expanded region-specific EMS numbers and AED freshness pipeline  
- [ ] Android / cross-platform companion beyond App Inventor  
- [ ] Optional privacy-preserving cloud sync for classroom programs  
- [ ] Smaller model packaging / download footprint  

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| **Camera black / no coaching** | Physical device required. Check Camera permission. Restart session. Confirm `isRunning` Live pill. |
| **Skeleton jumps between people** | Improve side angle so rescuer is upright and patient is horizontal. Ensure good lighting. Latest builds score posture + sticky lock. |
| **Chest box bounces with hands** | Update to builds that anchor the box to patient torso / horizontal YOLO–Vision box, not wrists. |
| **No YOLOv11 pill** | Confirm `yolo11n.mlpackage` is in `Resources/` and the target rebuilt (Xcode compiles Core ML). Check console for `YOLO: yolo11n ready`. |
| **No AI Model pill** | Confirm `movenet_thunder.tflite` is bundled; check TensorFlow Lite local package resolves. |
| **No LiDAR Depth pill** | Needs LiDAR hardware + ARKit path. Clean the depth sensor; grant Camera; Pro/Max device. Non-LiDAR still coaches via pose + calibration. |
| **Depth always shallow/deep** | Run **Calibrate** after good compressions. Prefer LiDAR device. Check phone height/angle. |
| **CPM wildly wrong** | Stabilize the phone. Fuse needs clear wrist vertical motion; avoid extreme motion blur. |
| **ChatCPR / Emergency LLM silent** | Add ChatGPT API key; check network; verify secret file is loaded (no key → on-device features still work). |
| **Speech not recognizing answers** | Microphone + Speech permissions; speak the locale’s yes/no tokens; reduce room noise. |
| **AED map empty** | Confirm `WORLD.geojson` is in the bundle (~59 MB). Location permission required for distance sort. |
| **Share / export blank** | Use Progress export after a completed session; rebuild if share sheet host is stale. |
| **Signing / provisioning errors** | Select your Team; unique bundle ID; Automatic signing. Simulator destination OS must match an installed runtime (e.g. iPhone 16, OS 18.5). |
| **Build fails on Core ML / TFLite** | Clean build folder (⇧⌘K), rebuild. Ensure `LocalPackages/TensorFlowLite` is present. |

---

## Lessons Learned (Hard Problems We Solved)

1. **Accurate live coaching** — Weeks of threshold and hyperparameter tuning (temperature 0.35, max tokens 180, RAG k = 4, confidence ~0.30) until spoken tips matched the body.  
2. **Fusing four CV modalities** — Temporal filters, confidence-weighted fallbacks, unified AVCapture / ARKit Coach surface.  
3. **Two-body CPR scenes** — Posture scoring + sticky rescuer lock + horizontal patient boxes (Vision + YOLO).  
4. **Depth without a lab** — LiDAR fusion (72/28) + user calibration + research MSE comparison.  
5. **Rate noise** — Peak + zero-cross + FFT blend instead of a single estimator.  
6. **LLM safety** — On-device RAG, strict system prompts, low temperature, short max tokens; always escalate to EMS.  
7. **Cognitive load** — Hysteresis so the coach does not talk over every frame.  
8. **Secrets** — Keys never committed; placeholders only in docs.  
9. **App Inventor packaging** — Rebuild `.aia` from valid templates for Appathon demos.

---

## Congressional App Challenge Notes

Official written responses (description, inspiration, technical difficulties, 2.0 improvements, AI disclosure, teamwork takeaway) live in:

**[`CAC_Responses.md`](CAC_Responses.md)**

**AI used in development:** ChatGPT, Cursor, and Claude — for brainstorming, debugging assistance, and draft copy. We designed features, wrote and rewrote emergency dialogue, implemented SwiftUI / Python prototypes, and approved every coaching threshold against guideline bands and manikin practice.

**AI used at runtime:** on-device pose / detection models; ChatCPR and some emergency answers via the **ChatGPT API** with RAG over CPR knowledge chunks.

---

## Contributing

We welcome careful contributions that improve safety, clarity, and measurement quality.

1. Fork and create a feature branch (`git checkout -b feature/your-idea`).  
2. Keep changes focused (one concern per PR).  
3. Do **not** commit API keys, patient data, or private session exports.  
4. Test on a physical device with camera and microphone.  
5. Update this README when behavior changes.  
6. Open a pull request with motivation, approach, and test plan.

High-value areas: localization, accessibility, calibration UX, evaluation scripts, clearer Emergency copy, multi-rescuer scene logic.

---

## Acknowledgments

- **Lalithendra Reddy Bhima** and **Bhavika Bhima** — creators  
- **Madhava Bhima** — coach / mentor  
- CPR science and training communities whose public guidelines inform bystander education (we coach actionable steps; we do not claim affiliation with any certifying body in-app)  
- Apple Vision, ARKit, MapKit, Speech, and Core ML  
- MoveNet / TensorFlow Lite pose ecosystem  
- Ultralytics YOLOv11 Core ML packaging used for on-device object cues  
- OpenAI **ChatGPT API** for grounded conversational assistance  
- OpenAED-style worldwide AED data contributors  
- Modeling the Future Challenge / Save a Million Lives research context  

---

## License

Copyright (c) CPR Coach authors.

Unless a `LICENSE` file in this repository states otherwise, all rights are reserved. Contact the authors before redistribution, commercial use, or redistribution of bundled AED / training datasets.

This software is provided for **education and training**. It is **not** a medical device and makes **no clinical guarantees**.

---

## Contacts &amp; Links

| Item | Detail |
|------|--------|
| Creators | Lalithendra Reddy Bhima, Bhavika Bhima |
| Coach | Madhava Bhima |
| Demo video | [`docs/media/CPR_Coach_Demo.mp4`](docs/media/CPR_Coach_Demo.mp4) |
| Logo | [`docs/assets/CPRCoachLogo.png`](docs/assets/CPRCoachLogo.png) |
| iOS app | `VisionCPRCoach/` |
| CAC responses | [`CAC_Responses.md`](CAC_Responses.md) |
| Research / metrics | `Research Paper/` |
| MTFC project report | `Research Paper/MTFC_2027/CPR_Coach_MTFC_Project_Report.pdf` |
| App Inventor package | `CPRCoach-AppInventor/` |
| GitHub | [github.com/lalithbhima/CPRCoach](https://github.com/lalithbhima/CPRCoach) |

For collaboration, academic questions, or media requests, open a GitHub issue or contact the creators through your competition / school channel.

---

## Citation

```text
Bhima, L. R., & Bhima, B. (2026). Vision CPR Coach: Multimodal AI for
bystander CPR training and emergency guidance. Congressional App Challenge /
Modeling the Future Challenge project materials.
```

---

<p align="center">
  <strong>CPR Coach</strong> — practice with vision. Act with confidence. Call for help first.
</p>

<p align="center">
  <em>"The person standing right there can be the reason someone gets to go home."</em>
</p>
