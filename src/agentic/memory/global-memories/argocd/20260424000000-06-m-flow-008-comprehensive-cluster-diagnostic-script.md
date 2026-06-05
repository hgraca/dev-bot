---
date: 2026-04-24
keywords: ["argocd"]
---

## M-FLOW-008: Comprehensive cluster diagnostic script

Built a 28-section diagnostic/cleanup script (`pipe.sh`) for staging cluster operations via CloudShell.
For clusters managed via CloudShell copy-paste, maintain a living diagnostic script with numbered sections. Use `bash <<'EOF'` heredoc blocks. Include both diagnostic (read-only) and fix (mutating) sections, clearly labeled. Organize by concern: pods, Jobs, CronJobs, Argo CD, namespace-specific. This becomes reusable across sessions and shareable with teammates.
