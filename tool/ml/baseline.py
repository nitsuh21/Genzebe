#!/usr/bin/env python3
"""Step 0c: score the keyword rules against your labels.

This is the number every model has to beat. Metrics are computed by hand
(no scikit-learn yet) so each one is visible: accuracy, per-category
precision/recall/F1, and the most common mistakes. Results are saved to
baseline.json for comparison with the step-1 model.

    python3 tool/ml/baseline.py
"""
import argparse
import collections
import datetime
import json
import math
import os

from label import DEFAULT_DATA_DIR, UNKNOWN, load_jsonl, load_labels

GENERIC = {"expense", "income", "other"}  # isSpecificCategory() == false


def wilson(correct, total, z=1.96):
    """95% interval for a proportion; honest about small test sets."""
    if total == 0:
        return 0.0, 0.0
    p = correct / total
    centre = (p + z * z / (2 * total)) / (1 + z * z / total)
    half = z * math.sqrt(p * (1 - p) / total + z * z / (4 * total * total)) / (1 + z * z / total)
    return centre - half, centre + half


def per_category(pairs):
    tp, fp, fn = collections.Counter(), collections.Counter(), collections.Counter()
    for truth, guess in pairs:
        if truth == guess:
            tp[truth] += 1
        else:
            fp[guess] += 1
            fn[truth] += 1
    stats = {}
    for c in set(tp) | set(fp) | set(fn):
        precision = tp[c] / (tp[c] + fp[c]) if tp[c] + fp[c] else 0.0
        recall = tp[c] / (tp[c] + fn[c]) if tp[c] + fn[c] else 0.0
        f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
        stats[c] = {"support": tp[c] + fn[c], "precision": precision, "recall": recall, "f1": f1}
    return stats


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data-dir", default=DEFAULT_DATA_DIR)
    args = parser.parse_args()

    dataset = {row["id"]: row for row in load_jsonl(os.path.join(args.data_dir, "dataset.jsonl"))}
    labels = load_labels(os.path.join(args.data_dir, "labels.jsonl"))
    with open(os.path.join(args.data_dir, "meta.json")) as f:
        meta = json.load(f)

    # Label-free: how often the rules give up and only know the direction.
    predicted = collections.Counter(row["predicted"] for row in dataset.values())
    generic_share = sum(predicted[c] for c in GENERIC) / max(len(dataset), 1)
    print(f"All {len(dataset)} transactions (parser v{meta['parserVersion']}): "
          f"rules gave only a direction for {generic_share:.0%}")

    labelled = [(labels[i], dataset[i]["predicted"]) for i in labels if i in dataset and labels[i] != UNKNOWN]
    skipped = sum(1 for i in labels if labels[i] == UNKNOWN)
    if not labelled:
        raise SystemExit("no labels yet; run tool/ml/label.py")

    correct = sum(truth == guess for truth, guess in labelled)
    low, high = wilson(correct, len(labelled))
    print(f"\nTest set: {len(labelled)} labelled, {skipped} 'can't tell' (excluded)")
    print(f"Accuracy: {correct / len(labelled):.1%}  (95% interval {low:.0%}–{high:.0%})")

    stats = per_category(labelled)
    macro_f1 = sum(s["f1"] for s in stats.values() if s["support"]) / max(1, sum(1 for s in stats.values() if s["support"]))
    print(f"Macro F1: {macro_f1:.2f}  (every category counts equally, however rare)\n")
    print(f"{'category':<14}{'support':>8}{'precision':>11}{'recall':>8}{'F1':>6}")
    for c, s in sorted(stats.items(), key=lambda kv: -kv[1]["support"]):
        if s["support"]:
            print(f"{c:<14}{s['support']:>8}{s['precision']:>11.2f}{s['recall']:>8.2f}{s['f1']:>6.2f}")

    mistakes = [(t, g) for t, g in labelled if t != g]
    gave_up = sum(1 for _, g in mistakes if g in GENERIC)
    print(f"\n{len(mistakes)} mistakes: {gave_up} where the rules only knew the direction, "
          f"{len(mistakes) - gave_up} where they picked the wrong category")
    print("Most common (truth → rules said):")
    for (t, g), n in collections.Counter(mistakes).most_common(10):
        print(f"  {n:>3}  {t} → {g}")

    result = {
        "scoredAt": datetime.datetime.now().isoformat(timespec="seconds"),
        "model": "keyword rules",
        "parserVersion": meta["parserVersion"],
        "n": len(labelled),
        "accuracy": correct / len(labelled),
        "accuracy95": [low, high],
        "macroF1": macro_f1,
        "perCategory": stats,
    }
    with open(os.path.join(args.data_dir, "baseline.json"), "w") as f:
        json.dump(result, f, indent=2)


if __name__ == "__main__":
    main()
