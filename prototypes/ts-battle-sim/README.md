# TypeScript battle sim (set aside)

The first playable prototype: a rules engine, AI opponent and canvas UI for a
small tabletop battle. Kept for reference while the real project moves to Godot.
It uses only invented placeholder units.

Run from this folder (Node 22.18+):

    node --test "tests/**/*.test.ts"    # 41 tests
    node tools/simulate.ts              # AI-vs-AI balance run
    npm install && npm run dev          # browser build (needs Vite)
