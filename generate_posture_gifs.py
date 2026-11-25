#!/usr/bin/env python3
"""
Gera 5 GIFs animados limpos e de alto contraste (560x480) em TELA DIVIDIDA (Frente + Lado/Zoom).
Sem textos espremidos dentro do GIF (os títulos e instruções ficam nos widgets nativos do Flutter),
permitindo bonecos muito maiores, espaçados e fáceis de visualizar de longe.
"""

import os
import math
import numpy as np
import cv2
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = "/home/luis/teste-movimento/mobile_app/assets/gifs"
os.makedirs(OUT_DIR, exist_ok=True)

W, H = 560, 460


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_dict(d0, d1, t):
    s = 0.5 - 0.5 * math.cos(math.pi * t)
    out = {}
    for k in d0:
        x0, y0 = d0[k]
        x1, y1 = d1[k]
        out[k] = (lerp(x0, x1, s), lerp(y0, y1, s))
    return out


def map_to_box(pt, box):
    bx, by, bw, bh = box
    return (int(bx + pt[0] * bw), int(by + pt[1] * bh))


def draw_mannequin(img, pts_norm, box, is_hold, is_side_view=False, highlight_keys=None):
    highlight_keys = highlight_keys or set()
    pts = {k: map_to_box(v, box) for k, v in pts_norm.items()}

    bx, by, bw, bh = box
    floor_y = int(by + 0.91 * bh)
    cv2.line(img, (bx + 16, floor_y), (bx + bw - 16, floor_y), (110, 150, 170), 3)

    limb_color = (118, 230, 0) if is_hold else (0, 225, 255)  # BGR
    torso_fill = (45, 115, 15) if is_hold else (0, 105, 140)
    highlight_color = (140, 50, 255)

    if not is_side_view:
        torso_poly = np.array([
            pts["LEFT_SHOULDER"],
            pts["RIGHT_SHOULDER"],
            pts["RIGHT_HIP"],
            pts["LEFT_HIP"],
        ], dtype=np.int32)
        cv2.fillPoly(img, [torso_poly], torso_fill)
        cv2.polylines(img, [torso_poly], True, limb_color, 5, cv2.LINE_AA)

        bones = [
            ("LEFT_SHOULDER", "LEFT_ELBOW", "ombro"),
            ("LEFT_ELBOW", "LEFT_WRIST", "cotovelo"),
            ("RIGHT_SHOULDER", "RIGHT_ELBOW", "ombro"),
            ("RIGHT_ELBOW", "RIGHT_WRIST", "cotovelo"),
            ("LEFT_HIP", "LEFT_KNEE", "quadril"),
            ("LEFT_KNEE", "LEFT_ANKLE", "joelho"),
            ("RIGHT_HIP", "RIGHT_KNEE", "quadril"),
            ("RIGHT_KNEE", "RIGHT_ANKLE", "joelho"),
        ]
        for a, b, tag in bones:
            col = highlight_color if (tag in highlight_keys and not is_hold) else limb_color
            cv2.line(img, pts[a], pts[b], (0, 0, 0), 16, cv2.LINE_AA)
            cv2.line(img, pts[a], pts[b], col, 10, cv2.LINE_AA)

        foot_bones = [
            ("LEFT_ANKLE", "LEFT_HEEL"),
            ("LEFT_HEEL", "LEFT_FOOT_INDEX"),
            ("LEFT_ANKLE", "LEFT_FOOT_INDEX"),
            ("RIGHT_ANKLE", "RIGHT_HEEL"),
            ("RIGHT_HEEL", "RIGHT_FOOT_INDEX"),
            ("RIGHT_ANKLE", "RIGHT_FOOT_INDEX"),
        ]
        foot_col = (130, 60, 255) if not is_hold else (118, 230, 0)
        for a, b in foot_bones:
            cv2.line(img, pts[a], pts[b], (0, 0, 0), 13, cv2.LINE_AA)
            cv2.line(img, pts[a], pts[b], foot_col, 7, cv2.LINE_AA)

        mid_sh = (
            (pts["LEFT_SHOULDER"][0] + pts["RIGHT_SHOULDER"][0]) // 2,
            (pts["LEFT_SHOULDER"][1] + pts["RIGHT_SHOULDER"][1]) // 2,
        )
        cv2.line(img, pts["NOSE"], mid_sh, (0, 0, 0), 14, cv2.LINE_AA)
        cv2.line(img, pts["NOSE"], mid_sh, limb_color, 8, cv2.LINE_AA)
        cv2.circle(img, pts["NOSE"], 21, (0, 0, 0), -1, cv2.LINE_AA)
        cv2.circle(img, pts["NOSE"], 17, torso_fill, -1, cv2.LINE_AA)
        cv2.circle(img, pts["NOSE"], 17, limb_color, 4, cv2.LINE_AA)

        for k, p in pts.items():
            if k == "NOSE":
                continue
            cv2.circle(img, p, 8, (0, 0, 0), -1, cv2.LINE_AA)
            cv2.circle(img, p, 5, (255, 255, 255), -1, cv2.LINE_AA)

    else:
        cv2.line(img, pts["SHOULDER"], pts["HIP"], (0, 0, 0), 26, cv2.LINE_AA)
        cv2.line(img, pts["SHOULDER"], pts["HIP"], torso_fill, 18, cv2.LINE_AA)
        cv2.line(img, pts["SHOULDER"], pts["HIP"], limb_color, 5, cv2.LINE_AA)

        side_bones = [
            ("HIP", "KNEE", "quadril"),
            ("KNEE", "ANKLE", "joelho"),
            ("SHOULDER", "ELBOW", "ombro"),
            ("ELBOW", "WRIST", "cotovelo"),
        ]
        for a, b, tag in side_bones:
            col = highlight_color if (tag in highlight_keys and not is_hold) else limb_color
            cv2.line(img, pts[a], pts[b], (0, 0, 0), 16, cv2.LINE_AA)
            cv2.line(img, pts[a], pts[b], col, 10, cv2.LINE_AA)

        foot_col = (130, 60, 255) if not is_hold else (118, 230, 0)
        for a, b in [("ANKLE", "HEEL"), ("HEEL", "FOOT_INDEX"), ("ANKLE", "FOOT_INDEX")]:
            cv2.line(img, pts[a], pts[b], (0, 0, 0), 14, cv2.LINE_AA)
            cv2.line(img, pts[a], pts[b], foot_col, 8, cv2.LINE_AA)

        cv2.line(img, pts["NOSE"], pts["SHOULDER"], (0, 0, 0), 14, cv2.LINE_AA)
        cv2.line(img, pts["NOSE"], pts["SHOULDER"], limb_color, 8, cv2.LINE_AA)
        cv2.circle(img, pts["NOSE"], 21, (0, 0, 0), -1, cv2.LINE_AA)
        cv2.circle(img, pts["NOSE"], 17, torso_fill, -1, cv2.LINE_AA)
        cv2.circle(img, pts["NOSE"], 17, limb_color, 4, cv2.LINE_AA)
        eye_pt = (pts["NOSE"][0] + 13, pts["NOSE"][1] - 3)
        cv2.circle(img, eye_pt, 4, (255, 255, 255), -1, cv2.LINE_AA)

        for k, p in pts.items():
            if k == "NOSE":
                continue
            cv2.circle(img, p, 9, (0, 0, 0), -1, cv2.LINE_AA)
            cv2.circle(img, p, 6, (255, 255, 255), -1, cv2.LINE_AA)


def draw_calf_zoom_panel(img, t, is_hold, box):
    bx, by, bw, bh = box
    s = 0.5 - 0.5 * math.cos(math.pi * t)

    floor_y = int(by + 0.88 * bh)
    cv2.line(img, (bx + 18, floor_y), (bx + bw - 18, floor_y), (150, 200, 220), 4)

    toe = (int(bx + 0.70 * bw), int(by + 0.86 * bh))
    heel_y = lerp(0.86, 0.62, s)
    ankle_y = lerp(0.75, 0.52, s)
    knee_y = lerp(0.24, 0.14, s)

    heel = (int(bx + 0.35 * bw), int(by + heel_y * bh))
    ankle = (int(bx + 0.45 * bw), int(by + ankle_y * bh))
    knee = (int(bx + 0.47 * bw), int(by + knee_y * bh))

    limb_color = (118, 230, 0) if is_hold else (0, 225, 255)
    calf_color = (118, 230, 0) if is_hold else (140, 60, 255)

    calf_bulge_x = int(bx + (0.29 - 0.04 * s) * bw)
    calf_bulge_y = int(by + lerp(0.46, 0.32, s) * bh)
    calf_poly = np.array([knee, (calf_bulge_x, calf_bulge_y), ankle], dtype=np.int32)
    cv2.fillPoly(img, [calf_poly], (70, 30, 120) if not is_hold else (40, 110, 20))

    cv2.line(img, knee, ankle, (0, 0, 0), 22, cv2.LINE_AA)
    cv2.line(img, knee, ankle, limb_color, 14, cv2.LINE_AA)

    for a, b in [(ankle, heel), (heel, toe), (ankle, toe)]:
        cv2.line(img, a, b, (0, 0, 0), 18, cv2.LINE_AA)
        cv2.line(img, a, b, calf_color, 11, cv2.LINE_AA)

    pulse_r = int(22 + 5 * math.sin(t * math.pi))
    cv2.circle(img, heel, pulse_r, calf_color, 3, cv2.LINE_AA)

    ground_heel = (heel[0], floor_y)
    if ground_heel[1] - heel[1] > 12:
        cv2.arrowedLine(
            img,
            (heel[0] - 26, ground_heel[1]),
            (heel[0] - 26, heel[1]),
            (0, 234, 255),
            6,
            cv2.LINE_AA,
            tipLength=0.35,
        )

    for p in [knee, ankle, heel, toe]:
        cv2.circle(img, p, 10, (0, 0, 0), -1, cv2.LINE_AA)
        cv2.circle(img, p, 6, (255, 255, 255), -1, cv2.LINE_AA)


FRONT_NEUTRAL = {
    "NOSE": (0.50, 0.18),
    "LEFT_SHOULDER": (0.36, 0.30),
    "RIGHT_SHOULDER": (0.64, 0.30),
    "LEFT_ELBOW": (0.32, 0.44),
    "RIGHT_ELBOW": (0.68, 0.44),
    "LEFT_WRIST": (0.31, 0.57),
    "RIGHT_WRIST": (0.69, 0.57),
    "LEFT_HIP": (0.41, 0.55),
    "RIGHT_HIP": (0.59, 0.55),
    "LEFT_KNEE": (0.41, 0.72),
    "RIGHT_KNEE": (0.59, 0.72),
    "LEFT_ANKLE": (0.41, 0.86),
    "RIGHT_ANKLE": (0.59, 0.86),
    "LEFT_HEEL": (0.43, 0.90),
    "RIGHT_HEEL": (0.57, 0.90),
    "LEFT_FOOT_INDEX": (0.36, 0.91),
    "RIGHT_FOOT_INDEX": (0.64, 0.91),
}

SIDE_NEUTRAL = {
    "NOSE": (0.52, 0.18),
    "SHOULDER": (0.48, 0.30),
    "ELBOW": (0.48, 0.44),
    "WRIST": (0.50, 0.57),
    "HIP": (0.48, 0.55),
    "KNEE": (0.49, 0.72),
    "ANKLE": (0.47, 0.86),
    "HEEL": (0.42, 0.90),
    "FOOT_INDEX": (0.60, 0.91),
}

POSTURE_CONFIGS = {
    "ortostatica": {
        "left_label": "DE FRENTE",
        "right_label": "DE LADO",
        "highlight": {"ombro", "cotovelo"},
        "front_start": {
            **FRONT_NEUTRAL,
            "LEFT_ELBOW": (0.24, 0.41),
            "RIGHT_ELBOW": (0.76, 0.41),
            "LEFT_WRIST": (0.20, 0.52),
            "RIGHT_WRIST": (0.80, 0.52),
        },
        "front_target": FRONT_NEUTRAL,
        "side_start": {
            **SIDE_NEUTRAL,
            "ELBOW": (0.58, 0.42),
            "WRIST": (0.66, 0.50),
        },
        "side_target": SIDE_NEUTRAL,
        "front_arrows": [((0.16, 0.46), (0.28, 0.46)), ((0.84, 0.46), (0.72, 0.46))],
        "side_arrows": [((0.68, 0.47), (0.54, 0.47))],
    },
    "bracos_t": {
        "left_label": "DE FRENTE (90°)",
        "right_label": "DE LADO",
        "highlight": {"ombro"},
        "front_start": FRONT_NEUTRAL,
        "front_target": {
            **FRONT_NEUTRAL,
            "LEFT_ELBOW": (0.20, 0.30),
            "RIGHT_ELBOW": (0.80, 0.30),
            "LEFT_WRIST": (0.05, 0.30),
            "RIGHT_WRIST": (0.95, 0.30),
        },
        "side_start": SIDE_NEUTRAL,
        "side_target": {
            **SIDE_NEUTRAL,
            "ELBOW": (0.48, 0.30),
            "WRIST": (0.48, 0.30),
        },
        "front_arrows": [((0.15, 0.52), (0.12, 0.33)), ((0.85, 0.52), (0.88, 0.33))],
        "side_arrows": [((0.64, 0.52), (0.54, 0.32))],
    },
    "elevacao_panturrilha": {
        "left_label": "CORPO INTEIRO",
        "right_label": "ZOOM PANTURRILHA",
        "highlight": {"joelho"},
        "use_calf_zoom": True,
        "front_start": FRONT_NEUTRAL,
        "front_target": {
            "NOSE": (0.50, 0.12),
            "LEFT_SHOULDER": (0.36, 0.24),
            "RIGHT_SHOULDER": (0.64, 0.24),
            "LEFT_ELBOW": (0.31, 0.37),
            "RIGHT_ELBOW": (0.69, 0.37),
            "LEFT_WRIST": (0.35, 0.48),
            "RIGHT_WRIST": (0.65, 0.48),
            "LEFT_HIP": (0.41, 0.49),
            "RIGHT_HIP": (0.59, 0.49),
            "LEFT_KNEE": (0.41, 0.66),
            "RIGHT_KNEE": (0.59, 0.66),
            "LEFT_ANKLE": (0.41, 0.79),
            "RIGHT_ANKLE": (0.59, 0.79),
            "LEFT_HEEL": (0.43, 0.81),
            "RIGHT_HEEL": (0.57, 0.81),
            "LEFT_FOOT_INDEX": (0.36, 0.91),
            "RIGHT_FOOT_INDEX": (0.64, 0.91),
        },
        "front_arrows": [((0.20, 0.86), (0.20, 0.68)), ((0.80, 0.86), (0.80, 0.68))],
    },
    "agachamento_iso": {
        "left_label": "DE FRENTE",
        "right_label": "DE LADO (BRAÇO À FRENTE)",
        "highlight": {"joelho", "quadril", "ombro"},
        "front_start": FRONT_NEUTRAL,
        "front_target": {
            "NOSE": (0.50, 0.28),
            "LEFT_SHOULDER": (0.36, 0.40),
            "RIGHT_SHOULDER": (0.64, 0.40),
            "LEFT_ELBOW": (0.35, 0.41),
            "RIGHT_ELBOW": (0.65, 0.41),
            "LEFT_WRIST": (0.35, 0.39),
            "RIGHT_WRIST": (0.65, 0.39),
            "LEFT_HIP": (0.41, 0.63),
            "RIGHT_HIP": (0.59, 0.63),
            "LEFT_KNEE": (0.36, 0.76),
            "RIGHT_KNEE": (0.64, 0.76),
            "LEFT_ANKLE": (0.41, 0.87),
            "RIGHT_ANKLE": (0.59, 0.87),
            "LEFT_HEEL": (0.43, 0.90),
            "RIGHT_HEEL": (0.57, 0.90),
            "LEFT_FOOT_INDEX": (0.36, 0.91),
            "RIGHT_FOOT_INDEX": (0.64, 0.91),
        },
        "side_start": SIDE_NEUTRAL,
        "side_target": {
            "NOSE": (0.50, 0.27),
            "SHOULDER": (0.44, 0.38),
            "ELBOW": (0.66, 0.38),
            "WRIST": (0.88, 0.37),
            "HIP": (0.28, 0.62),
            "KNEE": (0.58, 0.74),
            "ANKLE": (0.45, 0.87),
            "HEEL": (0.39, 0.90),
            "FOOT_INDEX": (0.60, 0.91),
        },
        "front_arrows": [((0.50, 0.46), (0.50, 0.62))],
        "side_arrows": [
            ((0.58, 0.28), (0.86, 0.28)),
            ((0.22, 0.46), (0.22, 0.62)),
        ],
    },
    "duplo_biceps": {
        "left_label": "DE FRENTE (EM W)",
        "right_label": "DE LADO (90°)",
        "highlight": {"ombro", "cotovelo"},
        "front_start": FRONT_NEUTRAL,
        "front_target": {
            **FRONT_NEUTRAL,
            "LEFT_ELBOW": (0.20, 0.30),
            "RIGHT_ELBOW": (0.80, 0.30),
            "LEFT_WRIST": (0.20, 0.14),
            "RIGHT_WRIST": (0.80, 0.14),
        },
        "side_start": SIDE_NEUTRAL,
        "side_target": {
            **SIDE_NEUTRAL,
            "ELBOW": (0.52, 0.30),
            "WRIST": (0.52, 0.14),
        },
        "front_arrows": [((0.13, 0.36), (0.13, 0.15)), ((0.87, 0.36), (0.87, 0.15))],
        "side_arrows": [((0.66, 0.36), (0.66, 0.15))],
    },
}


def render_posture_frame(cfg, t, is_hold):
    img = np.zeros((H, W, 3), dtype=np.uint8)
    img[:] = (8, 10, 14)

    left_box = (12, 12, 262, 436)
    right_box = (286, 12, 262, 436)

    border_col = (118, 230, 0) if is_hold else (0, 215, 255)
    for bx, by, bw, bh in [left_box, right_box]:
        cv2.rectangle(img, (bx, by), (bx + bw, by + bh), (22, 20, 16), -1)
        cv2.rectangle(img, (bx, by), (bx + bw, by + bh), border_col, 2)

    f_pose = lerp_dict(cfg["front_start"], cfg["front_target"], t)
    draw_mannequin(
        img,
        f_pose,
        left_box,
        is_hold=is_hold,
        is_side_view=False,
        highlight_keys=cfg.get("highlight"),
    )

    for a_norm, b_norm in cfg.get("front_arrows", []):
        p0 = map_to_box(a_norm, left_box)
        p1 = map_to_box(b_norm, left_box)
        cv2.arrowedLine(img, p0, p1, (0, 0, 0), 10, cv2.LINE_AA, tipLength=0.35)
        cv2.arrowedLine(img, p0, p1, (0, 234, 255), 5, cv2.LINE_AA, tipLength=0.35)

    if cfg.get("use_calf_zoom"):
        draw_calf_zoom_panel(img, t, is_hold, right_box)
    else:
        s_pose = lerp_dict(cfg["side_start"], cfg["side_target"], t)
        draw_mannequin(
            img,
            s_pose,
            right_box,
            is_hold=is_hold,
            is_side_view=True,
            highlight_keys=cfg.get("highlight"),
        )
        for a_norm, b_norm in cfg.get("side_arrows", []):
            p0 = map_to_box(a_norm, right_box)
            p1 = map_to_box(b_norm, right_box)
            cv2.arrowedLine(img, p0, p1, (0, 0, 0), 10, cv2.LINE_AA, tipLength=0.35)
            cv2.arrowedLine(img, p0, p1, (0, 234, 255), 5, cv2.LINE_AA, tipLength=0.35)

    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    pil_img = Image.fromarray(rgb)
    draw = ImageDraw.Draw(pil_img)

    try:
        f_panel = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 15)
    except Exception:
        f_panel = ImageFont.load_default()

    draw.rounded_rectangle([(20, 20), (266, 50)], radius=6, fill=(0, 0, 0))
    draw.text((32, 26), cfg["left_label"], fill=(0, 229, 255), font=f_panel)

    draw.rounded_rectangle([(294, 20), (540, 50)], radius=6, fill=(0, 0, 0))
    draw.text((304, 26), cfg["right_label"], fill=(255, 234, 0), font=f_panel)

    return pil_img


def main():
    schedule = [
        (0.0, False),
        (0.20, False),
        (0.45, False),
        (0.75, False),
        (1.0, False),
        (1.0, True),
        (1.0, True),
        (1.0, True),
        (1.0, True),
        (1.0, True),
        (0.75, False),
        (0.40, False),
        (0.0, False),
    ]

    for pid, cfg in POSTURE_CONFIGS.items():
        frames = [render_posture_frame(cfg, t, hold) for (t, hold) in schedule]
        out_path = os.path.join(OUT_DIR, f"{pid}.gif")
        frames[0].save(
            out_path,
            save_all=True,
            append_images=frames[1:],
            duration=110,
            loop=0,
            optimize=True,
        )
        print(f"Gerado: {out_path} ({os.path.getsize(out_path) // 1024} KB)")


if __name__ == "__main__":
    main()
