---
date: 2026-09-25
keywords: ["design-review", "address-review", "trade-off", "product-decision"]
---

# A review finding that is the consequence of a requested change is a trade-off to surface, not a defect to fix

Moving the landing page's `Why DevBot?` list above the install instructions pushed the install command below the fold (card top ≈ y=996 against a 900px viewport). The design validation reported that as a failure — but the fold cost was the direct, unavoidable consequence of the ordering the user had asked for, not a defect in the implementation.

The wrong move is to satisfy the reviewer by reverting the instruction (putting install back above the list) or by quietly trimming the content until it fits. Both overrule a product decision with a design opinion, and neither would have been noticed as a silent reversal. What worked instead: measure the cost precisely, attribute it to the requested ordering, name the options (keep as-is / reverse the order / trim the list) and let the user decide — the user kept the requested order.

Two habits generalise. First, before "fixing" a review finding, ask whether the flagged thing is a defect or the accepted cost of a decision someone else owns; if it is the latter, the finding is a trade-off report — surface it with numbers and options rather than acting on it. Second, notice whose bar the criterion is: a reviewer's own quality bar (here, an above-the-fold CTA) is not automatically a requirement, so a "reject" against it is advisory until the decision owner confirms it.
