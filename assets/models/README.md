# Fatigue model

`tools/train_fatigue_model.py` writes the trained model here as
`fatigue_model.json`. The app loads it at startup; until it exists, the app
falls back to the velocity-loss baseline.
