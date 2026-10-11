#!/usr/bin/env python3
"""Step 0b: label a frozen, random test set of your transactions.

The first run draws --n transactions at random and freezes their ids in
test_ids.json; later runs only resume. The rules' guess is never shown, so
your labels can't drift toward it. Answers are appended to labels.jsonl after
every keystroke, so quitting at any point loses nothing.

    python3 tool/ml/label.py [--n 300]
"""
import argparse
import datetime
import json
import os
import random
import textwrap

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_DATA_DIR = os.path.join(ROOT, "tool", "ml", "data")

# Same ids as kCategoryCatalog (lib/features/transactions/domain/models/categories.dart).
CATEGORIES = [
    "groceries", "food", "transport", "shopping", "bills", "airtime", "rent",
    "health", "education", "entertainment", "savings", "fees", "atm",
    "transfer_out", "expense", "salary", "income", "transfer_in", "other",
]
UNKNOWN = "?"


def load_jsonl(path):
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return [json.loads(line) for line in f if line.strip()]


def load_labels(path):
    labels = {}
    for entry in load_jsonl(path):
        if entry["label"] is None:
            labels.pop(entry["id"], None)  # an undo
        else:
            labels[entry["id"]] = entry["label"]
    return labels


def frozen_test_ids(data_dir, dataset, n, seed):
    path = os.path.join(data_dir, "test_ids.json")
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    ids = random.Random(seed).sample([row["id"] for row in dataset], min(n, len(dataset)))
    with open(path, "w") as f:
        json.dump(ids, f, indent=1)
    return ids


def menu():
    cells = [f"{i + 1:>2} {c:<14}" for i, c in enumerate(CATEGORIES)]
    lines = ["".join(cells[i:i + 6]) for i in range(0, len(cells), 6)]
    lines.append("   s = can't tell   u = undo   q = quit")
    return "\n".join(lines)


def card(row, position, total):
    when = row["date"][:16].replace("T", " ")
    amount = f"ETB {row['amountMinor'] / 100:,.2f}"
    arrow = "OUT ↑" if row["direction"] == "out" else "IN ↓"
    print(f"\n{'─' * 30} {position}/{total} {'─' * 30}")
    print(f"{when} · {row['sender']} · {arrow} · {amount}")
    if row.get("merchant"):
        print(f"Counterparty: {row['merchant']}")
    print(textwrap.fill(row["body"], width=88, initial_indent="  ", subsequent_indent="  "))


def ask():
    while True:
        answer = input("label> ").strip().lower()
        if answer in ("s", "u", "q"):
            return answer
        if answer.isdigit() and 1 <= int(answer) <= len(CATEGORIES):
            return CATEGORIES[int(answer) - 1]
        matches = [c for c in CATEGORIES if c.startswith(answer)] if answer else []
        if len(matches) == 1:
            return matches[0]
        if matches:
            print(f"  which one? {', '.join(matches)}")
        else:
            print("  type a number, a category name, s, u or q")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--n", type=int, default=300, help="test-set size (first run only)")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--data-dir", default=DEFAULT_DATA_DIR)
    args = parser.parse_args()

    dataset = load_jsonl(os.path.join(args.data_dir, "dataset.jsonl"))
    if not dataset:
        raise SystemExit("no dataset; run tool/ml/export_sms.py first")
    by_id = {row["id"]: row for row in dataset}
    test_ids = [i for i in frozen_test_ids(args.data_dir, dataset, args.n, args.seed) if i in by_id]
    # Date order: neighbouring transactions jog the memory.
    test_ids.sort(key=lambda i: by_id[i]["date"])

    labels_path = os.path.join(args.data_dir, "labels.jsonl")
    labels = load_labels(labels_path)
    history = []
    print("What should the app show for each transaction? Use what you know, not only")
    print("what the SMS says: a transfer to a person you paid rent is `rent`.")
    print(menu())

    with open(labels_path, "a") as out:
        def record(tx_id, label):
            out.write(json.dumps({"id": tx_id, "label": label,
                                  "at": datetime.datetime.now().isoformat(timespec="seconds")}) + "\n")
            out.flush()

        pending = [i for i in test_ids if i not in labels]
        while pending:
            tx_id = pending[0]
            card(by_id[tx_id], len(test_ids) - len(pending) + 1, len(test_ids))
            answer = ask()
            if answer == "q":
                break
            if answer == "u":
                if not history:
                    print("  nothing to undo")
                    continue
                previous = history.pop()
                record(previous, None)
                pending.insert(0, previous)
                continue
            record(tx_id, UNKNOWN if answer == "s" else answer)
            history.append(pending.pop(0))
            if len(history) % 25 == 0:
                print("\n" + menu())

    done = len(load_labels(labels_path))
    print(f"\n{done}/{len(test_ids)} labelled. Run: python3 tool/ml/baseline.py")


if __name__ == "__main__":
    main()
