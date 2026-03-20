# Build Box

This repository consists of a `Dockerfile` which we use as a development environment and launch point for running CI/CD.

Key among the uses are the environment that you're currently running inside, as well as the Blink engine privately accessible to you via `http://gitlab/`, for which you are already authenticated via the `glab` CLI.

This image is built and hosted on pushing to main. Your local env will not update to reflect the changes you make as the image is only pulled when a new OpenCode instance is spawned (i.e. this image was pulled to form your environment when the conversation began).