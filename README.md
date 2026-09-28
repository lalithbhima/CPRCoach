# CPR Coach

<p align="center">
  <img src="docs/assets/CPRCoachLogo.png" alt="CPR Coach logo" width="220"/>
</p>

<p align="center">
  <strong>Vision CPR Coach</strong> — a multilingual, AI-powered iOS app that guides everyday people to perform high-quality CPR during emergencies and to practice beforehand with live computer-vision coaching.
</p>

<p align="center">
  <em>Training guidance only. Not a medical device. In a real emergency, call 911 (or your local emergency number) immediately.</em>
</p>

---

## Table of contents

1. [Demo video](#demo-video)
2. [The problem](#the-problem)
3. [Our solution](#our-solution)
4. [Key features](#key-features)
5. [How it works](#how-it-works)
6. [System architecture](#system-architecture)
7. [End-to-end pipeline](#end-to-end-pipeline)
8. [Math, computer vision, and real-world analysis](#math-computer-vision-and-real-world-analysis)
9. [Technical highlights](#technical-highlights)
10. [AI models and frameworks](#ai-models-and-frameworks)
11. [APIs and configuration](#apis-and-configuration)
12. [Performance metrics](#performance-metrics)
13. [Impact](#impact)
14. [Target audience](#target-audience)
15. [Project structure](#project-structure)
16. [Getting started](#getting-started)
17. [Roadmap](#roadmap)
18. [Troubleshooting and lessons learned](#troubleshooting-and-lessons-learned)
19. [Contributing](#contributing)
20. [Acknowledgements](#acknowledgements)
21. [License](#license)
22. [Contacts and links](#contacts-and-links)
23. [Citation](#citation)

---

## Demo video

Full product walkthrough (Coach, Emergency, Learn, ChatCPR, models, and evaluation narrative):

<video src="docs/media/CPR_Coach_Demo.mp4" controls width="720" poster="docs/assets/CPRCoachLogo.png"></video>

**[Watch / download the demo (`docs/media/CPR_Coach_Demo.mp4`)](docs/media/CPR_Coach_Demo.mp4)**

After you push to GitHub, the video also plays natively on the repository home page when this file is committed.

**Demo highlights (from the pitch transcript)**

- Live Coach tracks rescuer wrists, elbows, shoulders, and hips (skeletal keypoints) and highlights the patient’s chest with a guidance box.
- Personalized AI coaching on alignment, hand placement, compression rhythm, and estimated depth (for example: “Still not deep enough? Push harder.”).
- Emergency Voice AI walks through CPR decision-making; quick actions for emergency call, nearest hospital, and nearest AED.
- Learn tab for guidelines; ChatCPR for multilingual Q&A.
- Four vision modalities: YOLOv11 object cues, MoveNet + Apple Vision keypoints, LiDAR depth for 3D compression distance.
- Evaluation uses 3D-angle / form diagrams (lower = poorer form; higher = proper form).
- Stack: Python + SwiftUI; tools include Xcode, LLM API (OpenRouter), Apple Maps, and a worldwide AED GeoJSON database.

---

## The problem

Cardiac arrest can happen anywhere, at any time. Nearby people often have only seconds to act, and hesitation can be the difference between life and death.

| Scope | Approximate burden |
| --- | --- |
| California | ~65,000 cardiac arrests per year |
| United States | >400,000 per year |
| Global | ~5 million per year |

Research and public-health messaging in our pitch note that:

- Performing CPR can roughly **triple** survival odds versus no CPR.
- About **90%** of out-of-hospital cardiac arrests do not survive.
- Fewer than **3%** of people are trained to perform CPR.

Most of the time, the person who can save a life is not a doctor in the room — it is a bystander who needs clear, calm, high-quality guidance **before** EMS arrives.

---

## Our solution

**CPR Coach (Vision CPR Coach)** is a novel multilingual AI-powered iOS application that:

1. **Trains** people ahead of time with live camera coaching (rate, depth, hands, elbows, recoil).
2. **Guides** them during a suspected emergency with a voice assistant that walks through safety checks, EMS activation, AED retrieval, and compressions.
3. **Educates** with structured Learn modules and ChatCPR (RAG-grounded LLM answers).
4. **Locates** help via Apple Maps hospitals and a bundled worldwide AED database.

The product is built as training and decision support — never as a replacement for certified training or professional care.

---

## Key features

### Live Coach

- Real-time joint tracking of the rescuer (wrists, elbows, shoulders, hips).
- Chest guidance box for the patient / manikin region.
- Live metrics: compressions per minute (CPM), estimated depth (cm), elbow angle, hand placement, recoil, motion stability.
- Spoken coaching cues (“push harder,” rhythm and placement corrections).
- Optional **Calibrate** flow to personalize depth scale after good practice compressions.
- Immersive full-screen coaching mode when a session is running.
- Standby / Live / AI Model / LiDAR Depth status pills.

### Emergency Voice AI

- Dispatcher-style conversational flow: confirm emergency, age group, scene safety, responsiveness, breathing, call EMS, confirm call, get AED, start CPR, active coaching, recovery monitoring.
- Apple Speech recognition + text-to-speech.
- Quick actions: call local emergency number, find hospital, find AED.
- Session conversation log and summary when the voice session ends.

### Learn

- Professional-level modules:
  - Primary Assessment and Scene Safety
  - Chest Compressions and Technique
  - CPR Quality, Physiology, and Technology
  - AED, EMS Integration, and Post-Arrest Care
- Voice-guided lesson read-along.
- Pointer into ChatCPR for follow-up questions.

### ChatCPR

- Multilingual AI assistant for technique, emergencies, AEDs, and live-form questions.
- RAG over on-device CPR knowledge chunks (k = 4 in production).
- Suggestion chips and optional “Analyze my form” using live metrics.
- Grounded, short answers; always remind users to call EMS in true emergencies.

### More: Hospitals, AEDs, Progress, Calibration, Settings

| Feature | What it does |
| --- | --- |
| **Hospitals** | Apple Maps nearby emergency rooms; nearest badge; call emergency |
| **Nearest AED** | Bundled worldwide AED GeoJSON; distance-ranked stations on the map |
| **Progress** | Training score, latest session breakdown, charts, export / share |
| **Calibration** | Personalized depth scale history and baselines |
| **Settings** | Language, calibration toggle, about / architecture, training-data link |
| **Data Sources** | Transparency on voice, computer vision, validation, recommended practice order |

### Multilingual UI and voice

- Language onboarding plus in-Settings language switching.
- Localized UI strings and TTS/STT locale codes across major languages.

---

## How it works

At a high level, every camera frame is processed by **four modalities**, fused into CPR metrics, then turned into on-screen feedback and spoken coaching.

```text
                    +------------------+
                    |  iPhone Camera   |
                    |  (+ LiDAR ARKit) |
                    +--------+---------+
                             |
                             v
        +--------------------+--------------------+
        |         Multi-modal frame pipeline      |
        |  YOLOv11 | MoveNet | Apple Vision | LiDAR |
        +--------------------+--------------------+
                             |
                             v
                 +-----------+-----------+
                 | Pose filter + scene   |
                 | rescuer vs patient    |
                 +-----------+-----------+
                             |
                             v
                 +-----------+-----------+
                 | CPR metrics engine    |
                 | rate / depth / hands  |
                 | elbows / recoil       |
                 +-----------+-----------+
                             |
              +--------------+--------------+
              |                             |
              v                             v
     +--------+--------+          +---------+---------+
     | Coach UI + TTS  |          | RAG + LLM (Chat / |
     | voice cues      |          | Emergency Voice)  |
     +-----------------+          +-------------------+
```

---

## System architecture

| Layer | Responsibility | Primary tech |
| --- | --- | --- |
| **UI** | Tabs, glass/bubble design, immersive coach, sheets | SwiftUI |
| **Camera / AR** | Preview, LiDAR scene depth when available | AVFoundation, ARKit |
| **Vision** | Keypoints, detection, multi-person logic | MoveNet Thunder (TFLite), Apple Vision, YOLOv11 cues |
| **Metrics** | CPM, depth, placement, recoil, quality scores | Custom Swift engines + FFT / peak fusion |
| **Voice** | STT / TTS, emergency dialogue, live coach phrases | Apple Speech, AVSpeechSynthesizer |
| **Language model** | ChatCPR + emergency conversational answers | OpenRouter API + on-device RAG |
| **Maps / AED** | Hospitals and AED stations | MapKit / Apple Maps, `world.geojson` |
| **Persistence** | Sessions, calibration, language prefs | On-device storage (app sandboxed data) |
| **Research / offline** | Figures, MAPE/MSE, hyperparameter sweeps | Python (NumPy, Matplotlib, MoveNet scripts) |

**App navigation (main tabs)**

1. Coach  
2. Emergency  
3. Learn  
4. ChatCPR  
5. More (Hospitals, AEDs, Progress, Calibration, Settings)

---

## End-to-end pipeline

1. **Capture** — Camera frame (AVCapture) or ARKit camera frame on LiDAR devices.
2. **Detect** — YOLOv11-style object cues help scene understanding; MoveNet Thunder estimates full-body keypoints; Apple Vision body pose is used as a fallback / complement.
3. **Depth** — On supported devices, LiDAR / ARKit scene depth estimates 3D compression amplitude; otherwise motion amplitude + calibration approximate depth in cm.
4. **Filter** — Temporal pose filtering stabilizes joints and helps separate rescuer from patient / manikin.
5. **Measure** — Metrics engine computes:
   - Rate via peak intervals fused with FFT on wrist vertical motion  
   - Depth from 3D / calibrated amplitude  
   - Elbow extension, hand placement relative to chest target, recoil quality  
6. **Coach** — Rule engine + voice layer emits short, actionable cues; UI updates metrics grid and guidance card.
7. **Assist** — Emergency / ChatCPR retrieve top-k knowledge chunks (RAG), call the LLM with live metrics in context when relevant, speak or display the answer.
8. **Locate** — User can open Hospitals or AEDs; location + MapKit + GeoJSON power nearby help.
9. **Review** — Progress stores session scores for charts, export, and calibration history.

---

## Math, computer vision, and real-world analysis

CPR Coach does not “guess” form from a single RGB pixel. It combines geometry, signal processing, and guideline thresholds.

### Computer vision stack

| Modality | Role in the real world |
| --- | --- |
| **YOLOv11** | Object / scene cues that support understanding what is in frame |
| **MoveNet Thunder** | Fast full-body keypoints (wrists, elbows, shoulders, hips, etc.) |
| **Apple Vision** | On-device body pose fallback and complementary human rectangles / hands |
| **LiDAR (ARKit)** | Scene depth for 3D compression distance when hardware supports it |

### Core calculations

- **Compression rate (CPM)** — Wrist vertical trajectory → peak detection + discrete Fourier analysis; fused estimate (production blend emphasizes spectral stability when both signals exist). Target band: **100–120 CPM**.
- **Depth (cm)** — 3D depth amplitude and/or motion amplitude mapped through a calibration scale. Adult target band: **5–6 cm**.
- **Elbow angle** — 3D / 2D joint vectors at shoulder–elbow–wrist; coaching prefers near-locked arms (high extension, e.g. greater than ~165° in UI targets).
- **Hand placement** — Wrists relative to estimated chest target (shoulder/hip anatomy + guidance box). Labels: Centered, Too Far Left/Right, Too High/Low.
- **Recoil** — Completeness of upward motion between compressions (Full vs Incomplete).
- **Quality / confidence** — Weighted combination of rate, depth, pressure proxy, joint confidence, and consistency scores for UI pills and coaching gates.
- **3D form angles** — Offline / evaluation diagrams where lower angle quality indicates poor form and higher quality indicates proper form (used in research figures and pitch evaluation).

### Production LLM / RAG hyperparameters

| Parameter | Production value | Purpose |
| --- | --- | --- |
| Temperature | **0.35** | Stable, coach-like answers |
| Max tokens (live) | **180** | Short spoken / chat replies |
| RAG top-k | **4** | Grounding chunks per turn |
| Pose / confidence gate | **~0.30** | Reduce noisy coaching when joints are weak |

These were tuned against live practice sessions so guidance stays accurate without becoming verbose or hallucinated.

---

## Technical highlights

- Four-modality live frame pipeline on a phone, not a lab PC.
- Dual camera path: standard AVCapture and ARKit LiDAR path unified in one Coach preview.
- AHA-aligned targets encoded as explicit rules (rate, depth, recoil, placement) — the LLM does not invent CPR thresholds.
- On-device RAG knowledge base for ChatCPR and emergency voice grounding.
- Multilingual UI + speech locales.
- Progress analytics, session export/share, and personalized depth calibration.
- Research tooling in Python for session exports, MAPE/MSE figures, hyperparameter sweeps, and angle analysis.
- MIT App Inventor frontend exploration for Appathon-style demos (separate `.aia` under `CPRCoach-AppInventor/`).

---

## AI models and frameworks

| Component | Technology |
| --- | --- |
| Object detection cues | YOLOv11 |
| Pose estimation | MoveNet Thunder (TensorFlow Lite) |
| On-device pose / humans | Apple Vision |
| Depth | ARKit scene depth / LiDAR |
| App UI | SwiftUI |
| Camera / AR | AVFoundation, ARKit |
| Speech | Apple Speech (recognition), AVSpeechSynthesizer (TTS) |
| LLM access | OpenRouter chat completions API |
| Maps | MapKit / Apple Maps |
| AED data | Bundled worldwide GeoJSON (`world.geojson` / OpenAED-style stations) |
| Offline research | Python 3, NumPy, Matplotlib, TFLite MoveNet scripts |
| IDE / tooling | Xcode, Visual Studio Code / Cursor |

---

## APIs and configuration

**Never commit real keys.** Secrets are gitignored.

| Secret / service | Where to configure | Used for |
| --- | --- | --- |
| **OpenRouter API key** | `VisionCPRCoach/Config/secret.ts` → `OPENROUTER_API_KEY` | ChatCPR, Emergency Voice AI LLM turns |
| **Apple Maps / MapKit** | Entitlements + location permission (system) | Hospitals, AED map |
| **Speech / Mic / Camera** | Info.plist usage strings | Coach, Emergency, Chat voice |
| **AED database** | Bundled GeoJSON asset | Nearest AED |

Build copies `secret.ts` into the app bundle as JSON for runtime load (`SecretsLoader`). Optional fallback: `Config/Secrets.swift`.

Example shape (placeholder only):

```ts
export const OPENROUTER_API_KEY = "sk-or-v1-YOUR_KEY_HERE";
```

---

## Performance metrics

Evaluated on live coaching session exports (idle / unknown frames filtered; shallow-depth calibration adjustments applied in analysis scripts). Display figures used in research / pitch materials:

| Metric | Result | Meaning |
| --- | --- | --- |
| **MAPE (compression rate)** | **2.93%** | Mean absolute percentage error vs session references |
| **MSE (depth)** | **0.31 cm²** | Depth error under fused / calibrated estimation |
| **Precision** | **96.89%** | Coaching feedback reliability (positive predictive) |
| **Recall** | **97.29%** | Coverage of relevant coaching events |
| **F1** | **97.06** | Harmonic balance of precision and recall |
| **LiDAR impact** | Large depth-error reduction vs pose-only path (~75% narrative in figure set) | 3D depth fusion vs camera-only amplitude |

Additional research artifacts live under `Research Paper/` (statistics figures, hyperparameter sweeps, MTFC actuarial project report).

---

## Impact

CPR Coach aims to shrink the gap between “I have never been trained” and “I can start useful compressions now.”

- **Practice before crisis** — Live form feedback builds muscle memory on rate, depth, and hands.
- **Support during crisis** — Voice AI reduces cognitive load with step-by-step checks and EMS/AED prompts.
- **Scale** — A phone-based coach can reach populations far beyond classroom certification seats.
- **Actuarial / public-health lens** — Our MTFC-style modeling treats improved bystander CPR as a mortality-risk mitigation pathway (see `Research Paper/MTFC_2027/`).

The long-term vision stated in our demo close: tools like CPR Coach help bystanders save lives at community scale — “save millions of lives” as an aspiration grounded in better access to high-quality CPR, not as a clinical claim.

---

## Target audience

- Everyday people who may witness cardiac arrest and need guidance before EMS arrives.
- Students and families practicing on a manikin or training setup.
- Schools, clubs, and community programs that want a practice companion beside formal certification.
- Researchers and builders studying multimodal CPR feedback (vision + voice + RAG).

**Not for:** replacing licensed medical care, diagnosing patients, or delaying a call to emergency services.

---

## Project structure

```text
APPChallenge/
├── README.md
├── docs/
│   ├── assets/CPRCoachLogo.png
│   └── media/CPR_Coach_Demo.mp4
├── VisionCPRCoach/                 # Main iOS app (SwiftUI)
│   ├── Config/secret.ts            # OpenRouter key (gitignored)
│   └── VisionCPRCoach/             # Sources, resources, localizations
├── VisionCPRCoach.xcodeproj/
├── Research Paper/                 # Metrics, figures, MTFC report
├── CPRCoach-AppInventor/           # MIT App Inventor frontend (.aia)
├── TrainingVideo/                  # Practice / export media
└── scripts/                        # Helper scripts
```

---

## Getting started

### Requirements

- macOS with Xcode (recent stable)
- iPhone recommended (LiDAR devices unlock full depth path; non-LiDAR still coaches via pose + calibration)
- OpenRouter API key for ChatCPR / LLM emergency turns

### Build and run

1. Clone this repository.
2. Open `VisionCPRCoach.xcodeproj` (or the workspace under `VisionCPRCoach/`) in Xcode.
3. Set your Team / signing for a physical device.
4. Add your OpenRouter key to `VisionCPRCoach/Config/secret.ts`.
5. Build and run on a device (camera + microphone required).
6. Grant Camera, Microphone, Speech, and Location permissions when prompted.

### First-run flow

1. Choose language.  
2. Welcome screen.  
3. Open **Coach** → Start Coaching.  
4. Explore **Emergency**, **Learn**, **ChatCPR**, and **More**.

---

## Roadmap

### Completed

- [x] Live Coach with multi-joint tracking and spoken cues  
- [x] Four-modality vision path (YOLO cues, MoveNet, Apple Vision, LiDAR)  
- [x] Emergency Voice AI guided flow + call / hospital / AED actions  
- [x] Learn modules with voice read-along  
- [x] ChatCPR with RAG + OpenRouter  
- [x] Hospitals (Apple Maps) and worldwide AED GeoJSON  
- [x] Progress, session export/share, calibration history  
- [x] Multilingual UI / speech  
- [x] Hyperparameter tuning for live LLM + pose gates  
- [x] Research metrics (MAPE, MSE, precision / recall / F1) and MTFC report draft  
- [x] MIT App Inventor frontend packaging for competition demos  

### Future work

- [ ] Stronger on-device model packaging and smaller download footprint  
- [ ] Broader clinical / instructor validation studies  
- [ ] Richer offline LLM / RAG when network is unavailable  
- [ ] Expanded language coverage and region-specific EMS numbers  
- [ ] Deeper AED data freshness pipeline  
- [ ] Android / cross-platform companion (beyond App Inventor prototype)  
- [ ] Optional cloud sync for training programs (privacy-preserving)  

---

## Troubleshooting and lessons learned

These are the hard problems we actually hit while building CPR Coach (from development history), and how we dealt with them.

### 1. Accurate live coaching (the hardest part)

**Problem:** Feedback had to feel like a real coach — fast, specific, and trustworthy. Wrong depth or rate cues confuse users and destroy trust.

**What we did:** Weeks of hyperparameter and threshold tuning (temperature 0.35, max tokens 180, RAG k = 4, pose confidence gates ~0.30), fusing advanced CV modalities, and validating against exported practice sessions until spoken tips matched what the body was doing.

### 2. Aligning and fusing multiple CV models

**Problem:** MoveNet, Apple Vision, YOLO cues, and LiDAR disagree under occlusion, odd camera angles, or multi-person frames. Naive fusion produced jittery skeletons and wrong chest boxes.

**What we did:** Temporal pose filters, rescuer-vs-patient scene logic, confidence-weighted fallbacks (Vision when MoveNet is weak), and a unified camera surface so LiDAR and non-LiDAR paths share one Coach UI.

### 3. Giving proper commands to the user

**Problem:** Over-talkative or conflicting prompts (“push harder” while depth was already deep) overwhelm bystanders.

**What we did:** Guideline-gated coaching (AHA bands), quality/confidence demotion of weak detections, short TTS phrases, and separate Emergency dialogue states so the app asks one clear question at a time.

### 4. Depth without a manikin ground-truth lab

**Problem:** True centimeter depth is hard from RGB alone.

**What we did:** LiDAR scene depth when available; otherwise motion amplitude + **Calibrate** personalization; research scripts compare pose-only vs LiDAR-fusion MSE.

### 5. Rate estimation noise

**Problem:** Peak-only CPM drifts with shake; FFT-only can lag.

**What we did:** Fuse peak intervals with FFT on wrist vertical displacement for a stabler live rate.

### 6. LLM grounding and safety

**Problem:** General chat models may invent protocols or soft-pedal calling EMS.

**What we did:** On-device RAG chunks, strict system prompts (“call emergency services,” no fake org citations / diagnoses), low temperature, short max tokens.

### 7. Share sheet / export UX (iOS)

**Problem:** Progress export sometimes presented a blank share UI.

**What we did:** Item-based sheet presentation and a host view controller that presents `UIActivityViewController` in `viewDidAppear`.

### 8. App Inventor / Appathon frontend

**Problem:** Porting SwiftUI screens to MIT App Inventor required matching YaVersion, component versions, and allowed controls.

**What we did:** Rebuild `.aia` packages from a working export template; keep backend separate; mirror tab structure and copy for demos.

### 9. Secrets management

**Problem:** API keys must never ship in public commits.

**What we did:** `secret.ts` / `Secrets.swift` gitignored; document placeholders only in this README.

---

## Contributing

We welcome careful contributions that improve safety, clarity, and measurement quality.

1. Fork and create a feature branch.  
2. Keep changes focused (one concern per PR).  
3. Do not commit API keys, patient data, or private session exports.  
4. Test on a physical device with camera and microphone.  
5. Update docs / README sections when behavior changes.  
6. Open a pull request describing motivation, approach, and test plan.

Ideas that help most: localization fixes, accessibility, calibration UX, evaluation scripts, and clearer Emergency copy.

---

## Acknowledgements

- **Lalithendra Reddy Bhima** and **Bhavika Bhima** — creators  
- **Madhava Bhima** — coach / mentor  
- CPR science and training communities whose public guidelines inform bystander education (we coach actionable steps; we do not claim affiliation with any certifying body in-app)  
- Apple Vision, ARKit, MapKit, and Speech frameworks  
- MoveNet / TensorFlow Lite pose ecosystem  
- OpenRouter for LLM access  
- OpenAED-style worldwide AED data contributors  
- Modeling the Future Challenge / Save a Million Lives research context for our actuarial impact modeling  

---

## License

Copyright (c) CPR Coach authors.  

Unless a `LICENSE` file in this repository states otherwise, all rights are reserved. Contact the authors before redistribution, commercial use, or redistribution of bundled AED / training datasets.

This software is provided for **education and training**. It is **not** a medical device and makes **no clinical guarantees**.

---

## Contacts and links

| Item | Detail |
| --- | --- |
| Creators | Lalithendra Reddy Bhima, Bhavika Bhima |
| Coach | Madhava Bhima |
| Demo video | [`docs/media/CPR_Coach_Demo.mp4`](docs/media/CPR_Coach_Demo.mp4) |
| Logo | [`docs/assets/CPRCoachLogo.png`](docs/assets/CPRCoachLogo.png) |
| iOS app | `VisionCPRCoach/` |
| Research / metrics | `Research Paper/` |
| MTFC project report | `Research Paper/MTFC_2027/CPR_Coach_MTFC_Project_Report.pdf` |
| App Inventor package | `CPRCoach-AppInventor/` |

For collaboration, academic questions, or media requests, open a GitHub issue on this repository or contact the creators through your competition / school channel.

---

## Citation

If you use CPR Coach or its research artifacts in academic work, please cite the project report and this repository:

```text
Bhima, L. R., & Bhima, B. (2026). Vision CPR Coach: Multimodal AI for
bystander CPR training and emergency guidance. APPChallenge / MTFC project materials.
```

---

<p align="center">
  <strong>CPR Coach</strong> — practice with vision. Act with confidence. Call for help first.
</p>
