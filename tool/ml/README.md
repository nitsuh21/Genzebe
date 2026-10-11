# Categorization model

Learning project: replace the keyword rules in `inferCategory`
(`lib/features/sms_ingestion/domain/services/sms_parser.dart`) with a small
model that runs on the phone. Parsing (amount, direction, balance) stays
deterministic; only the category is learned.

| Step | What | Status |
|------|------|--------|
| 0 | Dataset, labels, baseline score of the keyword rules | dataset done; test set unlabelled |
| 1 | Character n-grams + logistic regression (scikit-learn) | [lesson 1](lessons/01_first_model.ipynb) |
| 2 | Export the weights, score in Dart, ship behind a confidence threshold | |
| 3 | On-device learning from the user's corrections | |
| 4 | Fine-tune a small multilingual transformer, compare with step 1 | |

## Step 0

```sh
python3 tool/ml/export_sms.py --serial <adb serial>   # phone plugged in, USB debugging on
python3 tool/ml/label.py                                # ~300 transactions, resumable
python3 tool/ml/baseline.py
```

Everything lands in `tool/ml/data/` (gitignored; the repo is public):

- `dataset.jsonl` — one parsed transaction per line, with the rules'
  prediction. Long digit runs (accounts, phones, references) are masked.
- `test_ids.json` — the frozen test set.
- `labels.jsonl` — your answers, append-only.
- `baseline.json` — the score every later model must beat.

## Lessons

```sh
/opt/homebrew/bin/python3.12 -m venv tool/ml/.venv     # once
tool/ml/.venv/bin/pip install -r tool/ml/requirements.txt
tool/ml/.venv/bin/jupyter lab tool/ml/lessons
```

Notebook outputs show real SMS. `.gitattributes` runs every `.ipynb` through
nbstripout on commit, so outputs never reach git. In a fresh clone, re-run
`tool/ml/.venv/bin/nbstripout --install` before committing a notebook.

## Why it is built this way

- **The test set is frozen.** It is drawn once at random and never trained
  on. A model scored on data it learned from looks better than it is.
  Steps 1+ train only on transactions outside `test_ids.json`.
- **Labelling is blind.** The rules' guess is never shown. Seeing it pulls
  your answer toward it and inflates the baseline.
- **Labels are what the app should show**, using what you know. A transfer
  to the person you pay rent is `rent`, even though the SMS can't say so.
  The gap this exposes is the ceiling for any text-only model: closing it
  needs history (same person, similar amount, same day each month), not
  better text understanding.
- **Accuracy comes with an interval.** With 300 labels, ±5 points is noise.
  Compare models on the same test set and look at the interval before
  celebrating.
- **Macro F1 next to accuracy.** If most transactions are `transfer_out`, a
  model can score high accuracy while never getting `health` right; macro F1
  weighs every category equally.
