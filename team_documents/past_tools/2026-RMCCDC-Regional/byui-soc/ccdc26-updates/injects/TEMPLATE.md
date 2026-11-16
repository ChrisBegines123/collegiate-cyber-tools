# Inject Response Templates

Use these templates as starting points for inject responses. Copy the relevant
template into a new file, fill in the placeholders, and export as PDF.

**Placeholder conventions:**
- `[PLACEHOLDER]` -- visible placeholder, replace with real text
- `<!-- PLACEHOLDER -->` -- HTML comment placeholder, replace inline

---
---

# TEMPLATE A: Technical Memorandum

Use for: incident reports, analysis results, implementation documentation,
system audit findings, detection script documentation.

---

# MEMORANDUM

| | |
|---|---|
| **TO:** | [Recipient -- e.g., Management / IT Security Team] |
| **FROM:** | [Team Role -- see list below] |
| **DATE:** | [Competition Date] |
| **RE:** | [Inject ID if given] -- [Descriptive Subject] |

---

## Executive Summary

[2-4 sentences. Lead with the most important finding or outcome. State what was
requested, what was done, and the conclusion.]

---

## [Investigation / Analysis / Implementation]

### [Section 1 Title]

[Describe what was done. Use tables for structured data:]

| Attribute | Value |
|-----------|-------|
| [Key] | [Value] |
| [Key] | [Value] |

[Use code blocks for commands run or evidence collected:]

```bash
# Command executed
[command here]
```

[Use screenshot placeholders where the inject requires visual evidence:]

**Screenshot:** [Description of what to capture]
<!-- INSERT SCREENSHOT: description_of_screen -->

### [Section 2 Title]

[Continue with additional sections as needed. Common patterns:]

**Systems Assessed:**

| System | IP | OS | Status | Notes |
|--------|-----|-----|--------|-------|
| [Name] | [IP] | [OS] | [Clean/Compromised/Remediated] | [Details] |
| [Name] | [IP] | [OS] | [Status] | [Details] |

**Timeline of Events:**

| Time | Event | Details |
|------|-------|---------|
| [HH:MM] | [Event] | [Details] |
| [HH:MM] | [Event] | [Details] |

**Evidence Collected:**

| Evidence | Location | Hash (SHA256) |
|----------|----------|---------------|
| [File/artifact] | [Path] | [Hash] |

---

## Findings

### Finding 1: [Title]

| Attribute | Value |
|-----------|-------|
| Severity | [Critical / High / Medium / Low] |
| Affected System(s) | [System names/IPs] |
| Description | [What was found] |
| Evidence | [How it was confirmed] |
| Remediation | [What was done to fix it] |

### Finding 2: [Title]

[Repeat pattern as needed]

---

## Conclusion

[Summarize findings and current status. Use **bold** for key outcomes.
Example: **All identified threats have been remediated and verified clean.**]

---

## Recommendations

1. [Highest priority recommendation]
2. [Second priority recommendation]
3. [Additional recommendations as needed]

---

## AI Tool Disclosure

[Include if AI tools were used to generate scripts or analysis]

The following AI tools were used to assist with this task:
- **[Tool Name]** -- Used for [purpose, e.g., script generation, log analysis]
- All AI-generated outputs were reviewed and validated by team members

---

*[Document type] prepared by [Team Role] -- [Date]*

---
---

# TEMPLATE B: Policy / Procedure Document

Use for: security policies, awareness training documents, IR procedures,
acceptable use policies, employee guidelines.

---

# [Policy Title]

**Policy Number:** [SEC-YYYY-NNN]
**Effective Date:** [Competition Date]
**Last Revised:** [Competition Date]
**Policy Owner:** [Department -- e.g., Information Security Department]

---

## 1. Purpose

[Why this policy exists. 2-3 sentences.]

---

## 2. Scope

This policy applies to:

- All full-time and part-time employees
- Contractors and temporary workers
- Third-party vendors with access to company systems
- [Additional scope items as relevant]

---

## 3. [Policy Section Title]

### 3.1 [Subsection]

[Policy content. Use bullet points for requirements:]

- [Requirement 1]
- [Requirement 2]
- [Requirement 3]

### 3.2 [Subsection]

[Continue as needed]

---

## 4. [Additional Sections]

[Add numbered sections as needed: Roles & Responsibilities, Procedures,
Compliance, Enforcement, Exceptions, etc.]

---

## N. Policy Review

This policy shall be reviewed [annually / quarterly / as needed] by the
[Policy Owner]. Updates will be communicated to all affected parties.

---

## Acknowledgment

I, ______________________, acknowledge that I have read, understand, and
agree to comply with the above policy.

**Signature:** ______________________
**Printed Name:** ______________________
**Date:** ______________________
**Department:** ______________________

---

## Sources

1. [Reference 1 -- e.g., NIST SP 800-53]
2. [Reference 2]

---

*Document prepared by [Team Role] -- [Date]*

---
---

# TEMPLATE C: Fill-In Analysis Report

Use for: firewall analysis, traffic capture reports, audit checklists --
any inject where you're filling in data from live investigation.

---

# MEMORANDUM

| | |
|---|---|
| **TO:** | [Recipient] |
| **FROM:** | [Team Role] |
| **DATE:** | [Competition Date] |
| **RE:** | [Inject ID] -- [Subject] |

---

## Summary

| Metric | Value |
|--------|-------|
| Analysis Start Time | <!-- HH:MM --> |
| Analysis End Time | <!-- HH:MM --> |
| Systems Analyzed | <!-- COUNT --> |
| Findings | <!-- COUNT --> |
| Critical/High Findings | <!-- COUNT --> |

---

## Findings

### Finding 1: <!-- TITLE -->

| Attribute | Value |
|-----------|-------|
| Source IP | <!-- IP --> |
| Destination IP | <!-- IP --> |
| Port/Protocol | <!-- PORT/PROTO --> |
| Count/Frequency | <!-- COUNT --> |
| Time Range | <!-- HH:MM - HH:MM --> |
| Assessment | <!-- Malicious / Suspicious / Benign --> |

**Evidence:**

<!-- INSERT SCREENSHOT -->

**Analysis:** <!-- Brief explanation of why this is notable -->

### Finding 2: <!-- TITLE -->

[Repeat pattern]

---

## Conclusion

<!-- Summary of findings and current posture -->

---

## Recommendations

1. <!-- Recommendation -->
2. <!-- Recommendation -->

---

*Report prepared by [Team Role] -- [Date]*

---
---

# REFERENCE: Common "FROM" Roles

Use whichever role best matches the inject topic:

- **Security Operations Team** -- general security work, monitoring, detection
- **Incident Response Team** -- breach investigation, malware analysis, forensics
- **Linux Systems Administration Team** -- Linux-specific audits, configuration
- **Windows Systems Administration Team** -- Windows/AD-specific work
- **Network Security Team** -- firewall, traffic analysis, network hardening
- **IT Infrastructure Team** -- general IT, logging, architecture
- **Information Security Department** -- policies, compliance, training

---

# REFERENCE: Inject Response Checklist

Before submitting any inject response, verify:

- [ ] Correct recipient in TO field
- [ ] Date matches competition day
- [ ] Executive summary present and concise
- [ ] All placeholder text replaced with real content
- [ ] Screenshots inserted where required
- [ ] Code blocks have correct syntax highlighting
- [ ] Evidence tables filled with real system data (IPs, hostnames, timestamps)
- [ ] Conclusion clearly states the outcome
- [ ] Recommendations are specific and actionable
- [ ] AI disclosure included if AI tools were used
- [ ] Footer attribution line present
- [ ] Spell-checked
- [ ] Exported as PDF
