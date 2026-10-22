---
date: 2026-10-22
keywords: ["docker", "docker-hub", "oci-index", "image-tag", "manifest"]
trigger-on: ["base-image-pin", "dockerfile-from", "image-availability-check"]
---

## A Docker Hub tag existing does not mean the image is pullable

Docker Hub registers an official image tag — and publishes its OCI index — before the per-arch manifests are pushed into it. During that window:

- `GET https://hub.docker.com/v2/repositories/library/<image>/tags/<tag>` returns 200 with a digest and a `last_updated`, and the tag page renders with a layers URL;
- the registry index itself is `{"manifests":[],"mediaType":"application/vnd.oci.image.index.v1+json"}`;
- the web API reports `images: []`;
- `docker pull` fails with `no matching manifest for linux/amd64 in the manifest list entries`, and so does `docker manifest inspect`.

Polling the tag API therefore produces false positives — a release pipeline can report "all tags present" while every `FROM` still cannot resolve. Check what actually matters: an `amd64` entry in the registry index (`GET https://registry-1.docker.io/v2/library/<image>/manifests/<tag>` with an anonymous token from `auth.docker.io` and an OCI index Accept header), or simply `docker pull`. Expect a lag of roughly one to two hours between the PHP source release and usable official images.
