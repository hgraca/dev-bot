---
date: 2026-11-09
keywords: ["argocd", "tls", "argocd-server-tls", "certificate-rotation", "rollout-restart"]
aliases: ["argocd cert renewal", "tls secret not reloading", "argocd expired certificate"]
---

## Renewing the Argo CD server certificate needs a restart, not just a secret update

Argo CD 3.6.x serves TLS itself on port 8080 and loads the certificate from Secret `argocd-server-tls` in the Argo CD namespace (the server logs `Loading TLS configuration from secret argocd/argocd-server-tls`). Behind a load balancer whose listener is plain TCP, the pod — not the LB — is the public TLS endpoint, so that secret is the only thing that matters. Updating `tls.crt`/`tls.key` in it is not enough: the server logged a load after the secret changed but kept serving the previous certificate, and only `kubectl -n argocd rollout restart deploy/argocd-server` made the new serial live (verified immediately afterwards). Always restart the deployment after a rotation and verify the certificate actually served — `openssl s_client -connect <host>:443 -servername <host> | openssl x509 -noout -dates -serial` — never the secret contents alone. Check the front door first too: an SSL listener with an ACM/IAM certificate terminates TLS at the LB, making the secret irrelevant.
