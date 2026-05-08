# Activation Hardening

Activation is not just “send people to reset password.”

## Before Opening Activation

- verify email identity mapping
- confirm SMTP deliverability
- confirm `EnableOpenServer` is temporary and tracked
- define when to re-disable permissive settings

## After Opening Activation

- monitor reset failures
- monitor duplicate-account confusion
- monitor external/guest address edge cases
- close permissive settings when initial activation wave stabilizes
