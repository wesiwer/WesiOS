# Wesi AI Streaming deployment

Production Wesi AI streaming is deployed automatically after relevant changes land on `main`.

The workflow `.github/workflows/deploy-wesi-ai-streaming.yml` watches the streaming gateway, relay, PocketBase AI hooks, persona build source, and the workflow itself. A successful run publishes the commit status `Wesi AI Streaming Deploy` only after the Relay, streaming gateway, Main PocketBase hooks, trust parity, health checks, and protected public edge have been verified.

Manual `workflow_dispatch` remains available for an explicit redeploy.
