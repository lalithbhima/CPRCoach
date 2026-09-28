# Vision CPR Coach — Live CPR Tracking (Python / MoveNet prototype)
# This file is the reference implementation for real-time CPR coaching:
#   • Detects body pose with MoveNet Thunder (TensorFlow Lite)
#   • Tracks wrist motion to estimate compression rate (CPM)
#   • Measures elbow angle, hand placement, and compression depth
#   • Returns live coaching feedback ("push faster", "push deeper", etc.)
# The iOS app ports this same logic into Swift (CPRMetricsEngine, CameraViewModel).

import cv2
import numpy as np
import tensorflow as tf
import time
from collections import deque

#  Model configuration: MoveNet Thunder runs at 256×256 input 
MODEL_PATH = "movenet_thunder.tflite"
INPUT_SIZE = 256

#  17 body keypoints MoveNet returns (same indices used in the Swift app) 
KEYPOINT_DICT = {
    "nose": 0,
    "left_eye": 1,
    "right_eye": 2,
    "left_ear": 3,
    "right_ear": 4,
    "left_shoulder": 5,
    "right_shoulder": 6,
    "left_elbow": 7,
    "right_elbow": 8,
    "left_wrist": 9,
    "right_wrist": 10,
    "left_hip": 11,
    "right_hip": 12,
    "left_knee": 13,
    "right_knee": 14,
    "left_ankle": 15,
    "right_ankle": 16,
}

#  Skeleton edges drawn on the camera overlay (shoulders → elbows → wrists) 
EDGES = [
    ("left_shoulder", "right_shoulder"),
    ("left_shoulder", "left_elbow"),
    ("left_elbow", "left_wrist"),
    ("right_shoulder", "right_elbow"),
    ("right_elbow", "right_wrist"),
    ("left_shoulder", "left_hip"),
    ("right_shoulder", "right_hip"),
    ("left_hip", "right_hip"),
]

#  Load the TFLite model once at startup 
interpreter = tf.lite.Interpreter(model_path=MODEL_PATH)
interpreter.allocate_tensors()

input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

#  Rolling buffers: wrist Y position + timestamps for CPM calculation 
wrist_y_history = deque(maxlen=120)
time_history = deque(maxlen=120)


def run_movenet(frame):
    """Run MoveNet on one camera frame → returns 17 keypoints (y, x, confidence)."""
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    input_image = tf.image.resize_with_pad(rgb, INPUT_SIZE, INPUT_SIZE)
    input_image = tf.expand_dims(input_image, axis=0)
    input_image = tf.cast(input_image, dtype=tf.uint8)

    interpreter.set_tensor(input_details[0]["index"], input_image.numpy())
    interpreter.invoke()

    keypoints = interpreter.get_tensor(output_details[0]["index"])
    return keypoints[0, 0, :, :]


def keypoint_to_pixel(kp, width, height):
    """Convert normalized keypoint (0–1) to pixel coordinates on the frame."""
    y, x, score = kp
    return int(x * width), int(y * height), score


def angle(a, b, c):
    """Elbow angle at point b (shoulder–elbow–wrist). Target: >165° for straight arms."""
    a = np.array(a)
    b = np.array(b)
    c = np.array(c)

    ba = a - b
    bc = c - b

    denom = np.linalg.norm(ba) * np.linalg.norm(bc)
    if denom == 0:
        return 0

    cos_angle = np.dot(ba, bc) / denom
    cos_angle = np.clip(cos_angle, -1.0, 1.0)

    return np.degrees(np.arccos(cos_angle))


def estimate_cpm():
    """
    Compression rate (CPM) from wrist Y peaks over time.
    AHA target: 100–120 compressions per minute.
    """
    if len(wrist_y_history) < 30:
        return 0

    y = np.array(wrist_y_history)
    t = np.array(time_history)

    # Count local maxima in wrist vertical motion = one compression each
    peaks = 0
    for i in range(1, len(y) - 1):
        if y[i] > y[i - 1] and y[i] > y[i + 1]:
            peaks += 1

    duration = t[-1] - t[0]
    if duration <= 0:
        return 0

    return (peaks / duration) * 60


def draw_pose(frame, keypoints):
    """Draw skeleton overlay on the live camera feed for visual feedback."""
    height, width, _ = frame.shape

    points = {}

    for name, idx in KEYPOINT_DICT.items():
        x, y, score = keypoint_to_pixel(keypoints[idx], width, height)
        points[name] = (x, y, score)

        if score > 0.3:
            cv2.circle(frame, (x, y), 5, (0, 255, 0), -1)

    for p1, p2 in EDGES:
        x1, y1, s1 = points[p1]
        x2, y2, s2 = points[p2]

        if s1 > 0.3 and s2 > 0.3:
            cv2.line(frame, (x1, y1), (x2, y2), (255, 180, 0), 2)

    return frame, points


def analyze_cpr(points):
    """
    Core CPR coaching logic — evaluates pose and returns live metrics + feedback.
    Priority order: visibility → hand placement → arms → rate → depth.
    """
    required = [
        "left_shoulder", "right_shoulder",
        "left_elbow", "right_elbow",
        "left_wrist", "right_wrist"
    ]

    # Not enough keypoints visible — ask user to move into frame
    if any(points[p][2] < 0.3 for p in required):
        return {
            "feedback": "Move body fully into camera view",
            "elbow_angle": 0,
            "cpm": 0,
            "amplitude": 0
        }

    ls = points["left_shoulder"][:2]
    rs = points["right_shoulder"][:2]
    le = points["left_elbow"][:2]
    re = points["right_elbow"][:2]
    lw = points["left_wrist"][:2]
    rw = points["right_wrist"][:2]

    # Elbow angle: both arms averaged (straight arms = better compressions)
    left_angle = angle(ls, le, lw)
    right_angle = angle(rs, re, rw)
    avg_elbow_angle = (left_angle + right_angle) / 2

    # Wrist midpoint tracks vertical compression motion
    wrist_mid_x = int((lw[0] + rw[0]) / 2)
    wrist_mid_y = int((lw[1] + rw[1]) / 2)

    shoulder_mid_x = int((ls[0] + rs[0]) / 2)
    shoulder_mid_y = int((ls[1] + rs[1]) / 2)

    wrist_y_history.append(wrist_mid_y)
    time_history.append(time.time())

    cpm = estimate_cpm()

    # Amplitude = peak-to-peak wrist travel (proxy for compression depth)
    if len(wrist_y_history) > 5:
        amplitude = max(wrist_y_history) - min(wrist_y_history)
    else:
        amplitude = 0

    dx = wrist_mid_x - shoulder_mid_x

    #  Coaching feedback rules (AHA-aligned targets) 
    if abs(dx) > 80:
        feedback = "Move hands toward the center of the chest"
    elif avg_elbow_angle < 150:
        feedback = "Straighten your arms more"
    elif cpm > 0 and cpm < 100:
        feedback = "Compress faster"
    elif cpm > 120:
        feedback = "Slow down slightly"
    elif amplitude < 20:
        feedback = "Push deeper"
    elif cpm == 0:
        feedback = "Begin compressions"
    else:
        feedback = "Good rhythm. Keep going"

    return {
        "feedback": feedback,
        "elbow_angle": avg_elbow_angle,
        "cpm": cpm,
        "amplitude": amplitude,
        "wrist_mid": (wrist_mid_x, wrist_mid_y),
        "shoulder_mid": (shoulder_mid_x, shoulder_mid_y)
    }


# Main live loop — webcam → pose → metrics → overlay → display
cap = cv2.VideoCapture(0)

if not cap.isOpened():
    print("Could not open webcam.")
    exit()

print("MoveNet Thunder CPR live demo running.")
print("Press Q to quit.")

while True:
    ret, frame = cap.read()

    if not ret:
        break

    frame = cv2.flip(frame, 1)

    # 1. Detect pose
    keypoints = run_movenet(frame)
    frame, points = draw_pose(frame, keypoints)

    # 2. Analyze CPR quality and get coaching feedback
    result = analyze_cpr(points)

    # 3. Draw wrist/shoulder markers and compression arrow on overlay
    if "wrist_mid" in result:
        cv2.circle(frame, result["wrist_mid"], 9, (255, 0, 255), -1)
        cv2.circle(frame, result["shoulder_mid"], 9, (0, 255, 255), -1)
        cv2.arrowedLine(
            frame,
            (result["wrist_mid"][0], result["wrist_mid"][1] - 60),
            result["wrist_mid"],
            (0, 255, 255),
            3
        )

    # 4. HUD: feedback text + live metrics on screen
    cv2.rectangle(frame, (10, 10), (620, 150), (0, 0, 0), -1)

    cv2.putText(
        frame,
        f"Feedback: {result['feedback']}",
        (20, 45),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.75,
        (255, 255, 255),
        2
    )

    cv2.putText(
        frame,
        f"Elbow Angle: {int(result['elbow_angle'])} deg",
        (20, 80),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.7,
        (0, 255, 255),
        2
    )

    cv2.putText(
        frame,
        f"Rate: {int(result['cpm'])} CPM | Motion: {int(result['amplitude'])}",
        (20, 115),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.7,
        (0, 255, 255),
        2
    )

    cv2.imshow("Vision CPR Coach - MoveNet Thunder Live", frame)

    if cv2.waitKey(1) & 0xFF == ord("q"):
        break

cap.release()
cv2.destroyAllWindows()
