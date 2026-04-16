# BurnRate Online AI Function

This folder adds an opt-in online advisor endpoint powered by Claude.

## 1) Install dependencies

```bash
cd functions
npm install
```

## 2) Set Anthropic secret (same pattern as DriveMate)

```bash
firebase functions:secrets:set ANTHROPIC_API_KEY
```

## 3) Build and deploy

```bash
npm run deploy
```

## Endpoint

- Function name: `onlineCoachChat`
- Region: `us-central1`
- Auth: Firebase ID token required in `Authorization: Bearer <token>`

