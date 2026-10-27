#!/usr/bin/env python3
"""Train the fatigue model from sets recorded in the app.

Each recorded set is labelled with how many reps the lifter had left at the
end (0 if they went to failure). That gives every rep a target: reps to
failure = (reps in the set + reps left at the end) - rep index. We fit a
ridge regression from the per-rep features the app computes to that target,
evaluate it on people it hasn't seen, and write the model the app loads.

Usage:
    python3 tools/train_fatigue_model.py ~/Downloads/fatigue-*.json
    python3 tools/train_fatigue_model.py data/ --features velocity
    python3 tools/train_fatigue_model.py data/ --dry-run

Accepts the per-set files from "Save & export" and the combined file from
"Export" (duplicates are dropped). Pure standard library; no installs.
"""

from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import math
import os
import sys
from collections import defaultdict

SCHEMA = "team9-fatigue-set/v1"

# Same names as RepFeatures.modelInputs in lib/fatigue/rep_features.dart.
FEATURE_SETS = {
    # Velocity-only baseline: what a velocity-based-training device sees.
    "velocity": ["rep_index", "velocity_loss", "duration_ratio"],
    # Everything: velocity plus range of motion and EMG.
    "full": [
        "rep_index",
        "velocity_loss",
        "duration_ratio",
        "rom_ratio",
        "emg_ratio",
        "emg_per_velocity_ratio",
    ],
}

# The app only predicts from the second rep on (the relative features need
# a baseline), so train on the same reps.
MIN_REP_INDEX = 2

DEFAULT_OUT = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "fatigue_model.json"
)


# ---------------------------------------------------------------- loading


def load_sets(paths: list[str]) -> list[dict]:
    files: list[str] = []
    for p in paths:
        if os.path.isdir(p):
            files += sorted(glob.glob(os.path.join(p, "**", "*.json"), recursive=True))
        else:
            files += sorted(glob.glob(os.path.expanduser(p)))
    sets: dict[tuple, dict] = {}
    for f in files:
        try:
            with open(f) as fh:
                data = json.load(fh)
        except (OSError, json.JSONDecodeError) as e:
            print(f"skip {f}: {e}", file=sys.stderr)
            continue
        if not isinstance(data, dict) or data.get("schema") != SCHEMA:
            continue
        for s in data["sets"] if "sets" in data else [data]:
            key = (s["labels"]["subject_id"], s["started_at"])
            sets[key] = s  # a per-set file and a combined export overlap
    return list(sets.values())


def rows_from_sets(sets: list[dict]) -> list[dict]:
    """One row per rep: features, target, and which subject/set it came from."""
    rows = []
    for set_id, s in enumerate(sets):
        reps = s["reps"]
        labels = s["labels"]
        total = len(reps) + int(labels["reps_in_reserve"])
        for r in reps:
            if r["rep_index"] < MIN_REP_INDEX:
                continue
            rows.append(
                {
                    "subject": labels["subject_id"],
                    "set": set_id,
                    "y": total - r["rep_index"],
                    "x": r,
                }
            )
    return rows


# ---------------------------------------------------------------- model


def solve(a: list[list[float]], b: list[float]) -> list[float]:
    """Solve a x = b by Gaussian elimination with partial pivoting."""
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(m[r][c]))
        m[c], m[p] = m[p], m[c]
        if abs(m[c][c]) < 1e-12:
            raise ValueError("singular system")
        for r in range(n):
            if r != c:
                f = m[r][c] / m[c][c]
                for k in range(c, n + 1):
                    m[r][k] -= f * m[c][k]
    return [m[i][n] / m[i][i] for i in range(n)]


def fit(rows: list[dict], features: list[str], ridge: float) -> dict:
    """Ridge regression on standardized features (intercept not penalized)."""
    n, d = len(rows), len(features)
    cols = [[row["x"][f] for row in rows] for f in features]
    mean = [sum(c) / n for c in cols]
    std = [math.sqrt(sum((v - mu) ** 2 for v in c) / n) or 1.0 for c, mu in zip(cols, mean)]
    z = [[(cols[j][i] - mean[j]) / std[j] for j in range(d)] for i in range(n)]
    y = [row["y"] for row in rows]
    y_mean = sum(y) / n
    xtx = [[sum(z[i][a] * z[i][b] for i in range(n)) + (ridge if a == b else 0) for b in range(d)] for a in range(d)]
    xty = [sum(z[i][a] * (y[i] - y_mean) for i in range(n)) for a in range(d)]
    coef = solve(xtx, xty)
    return {"features": features, "mean": mean, "std": std, "coef": coef, "intercept": y_mean}


def predict(model: dict, x: dict) -> float:
    rir = model["intercept"]
    for f, mu, sd, c in zip(model["features"], model["mean"], model["std"], model["coef"]):
        rir += c * (x[f] - mu) / sd
    return max(0.0, rir)


# ---------------------------------------------------------------- evaluation


def score(pairs: list[tuple[float, float]]) -> dict:
    """MAE, share within one rep, and how often a "stop" call was right."""
    if not pairs:
        return {"n": 0}
    err = [abs(p - y) for p, y in pairs]
    # The app says stop when predicted reps to failure is within the safety
    # margin (2). A good stop call is one made when the truth is also <= 2.
    stops = [(p, y) for p, y in pairs if math.floor(p) <= 2]
    return {
        "n": len(pairs),
        "mae": sum(err) / len(err),
        "within_1": sum(e <= 1 for e in err) / len(err),
        "stop_precision": (sum(y <= 2 for _, y in stops) / len(stops)) if stops else None,
    }


def cross_validate(rows: list[dict], features: list[str], ridge: float, group: str) -> dict:
    """Hold out each group (subject or set) in turn, train on the rest."""
    groups = sorted({r[group] for r in rows}, key=str)
    if len(groups) < 2:
        return {"n": 0}
    pairs = []
    for g in groups:
        train = [r for r in rows if r[group] != g]
        test = [r for r in rows if r[group] == g]
        if len(train) <= len(features):
            continue
        model = fit(train, features, ridge)
        pairs += [(predict(model, r["x"]), r["y"]) for r in test]
    return score(pairs)


def personal_cv(rows: list[dict], features: list[str], ridge: float) -> dict:
    """Per person: train only on their other sets, test on each held-out set."""
    pairs = []
    by_subject = defaultdict(list)
    for r in rows:
        by_subject[r["subject"]].append(r)
    for subject_rows in by_subject.values():
        sets = sorted({r["set"] for r in subject_rows})
        if len(sets) < 2:
            continue
        for s in sets:
            train = [r for r in subject_rows if r["set"] != s]
            test = [r for r in subject_rows if r["set"] == s]
            if len(train) <= len(features):
                continue
            model = fit(train, features, ridge)
            pairs += [(predict(model, r["x"]), r["y"]) for r in test]
    return score(pairs)


def mean_baseline(rows: list[dict], group: str) -> dict:
    """Always predict the training mean: the floor any model must beat."""
    pairs = []
    for g in {r[group] for r in rows}:
        train = [r["y"] for r in rows if r[group] != g]
        if not train:
            continue
        m = sum(train) / len(train)
        pairs += [(m, r["y"]) for r in rows if r[group] == g]
    return score(pairs)


def fmt(s: dict) -> str:
    if not s.get("n"):
        return "not enough data"
    stop = "–" if s["stop_precision"] is None else f"{s['stop_precision']:.0%}"
    return f"MAE {s['mae']:.2f} reps · within ±1: {s['within_1']:.0%} · stop calls right: {stop}  (n={s['n']})"


# ---------------------------------------------------------------- main


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+", help="exported JSON files or folders")
    ap.add_argument("--features", choices=sorted(FEATURE_SETS), default="full")
    ap.add_argument("--ridge", type=float, default=1.0, help="L2 penalty (default 1.0)")
    ap.add_argument("--out", default=DEFAULT_OUT, help="where to write the model")
    ap.add_argument("--dry-run", action="store_true", help="evaluate only; don't write the model")
    args = ap.parse_args()

    sets = load_sets(args.paths)
    rows = rows_from_sets(sets)
    subjects = sorted({s["labels"]["subject_id"] for s in sets})
    print(f"{len(sets)} sets, {len(subjects)} subjects ({', '.join(subjects)}), {len(rows)} training reps")
    if len(rows) <= len(FEATURE_SETS["full"]):
        print("Not enough data to train. Record more sets (to failure) first.", file=sys.stderr)
        return 1

    # Unseen people if we have several, otherwise unseen sets.
    group = "subject" if len(subjects) >= 2 else "set"
    held_out = "person" if group == "subject" else "set"
    print(f"\nEvaluated on each held-out {held_out} (trained on the rest):")
    print(f"  {'mean only':<16} {fmt(mean_baseline(rows, group))}")
    results = {}
    for name, feats in FEATURE_SETS.items():
        results[name] = cross_validate(rows, feats, args.ridge, group)
        print(f"  {name + ' model':<16} {fmt(results[name])}")
    print(f"\nPersonal models (each person's own other sets, {args.features} features):")
    print(f"  {'personal':<16} {fmt(personal_cv(rows, FEATURE_SETS[args.features], args.ridge))}")

    model = fit(rows, FEATURE_SETS[args.features], args.ridge)
    print(f"\nFinal {args.features} model, trained on everything:")
    for f, c in sorted(zip(model["features"], model["coef"]), key=lambda t: -abs(t[1])):
        print(f"  {f:<24} {c:+.3f} reps per std dev")
    print(f"  {'intercept':<24} {model['intercept']:.3f}")

    if args.dry_run:
        return 0
    cv = results[args.features]
    out = {
        "name": f"Trained ({args.features}, {len(subjects)} subj.)",
        "type": "linear_reps_to_failure",
        **model,
        "trained_at": dt.datetime.now().isoformat(timespec="seconds"),
        "training": {
            "sets": len(sets),
            "subjects": len(subjects),
            "reps": len(rows),
            "ridge": args.ridge,
            "cv_group": group,
            "cv_mae": cv.get("mae"),
        },
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w") as fh:
        json.dump(out, fh, indent=2)
    print(f"\nWrote {os.path.abspath(args.out)}. Rebuild the app to use it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
