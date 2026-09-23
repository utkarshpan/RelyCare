# RelyCare

### Offline-First Referral Continuity for Primary Healthcare

> **The network may fail. The referral shouldn't.**

RelyCare is an offline-first healthcare referral continuity platform designed to help referrals move reliably from **Primary Health Centres (PHCs)** to **District Hospitals**, even when internet connectivity is unreliable.

The system focuses on a simple but critical problem:

**A referral is not successful when a doctor clicks "Send".  
A referral is successful when the patient continues care at the next facility.**

---

## 🚨 The Problem

Healthcare referrals often cross multiple facilities, but the communication layer between them can be fragile.

A typical referral journey can break because of:

- 📶 Unreliable or unavailable internet connectivity
- 📄 Fragmented referral information
- 🔄 Delayed synchronization between facilities
- 👤 Patient identity variations between records
- 🏥 Lack of visibility at the receiving hospital
- 🔐 Need for secure, facility-level access control

When a referral is created at a PHC but the receiving hospital does not reliably receive or identify it, **continuity of care is affected**.

RelyCare is designed to address this gap.

---

# 💡 Our Solution

RelyCare provides an **offline-first referral continuity layer** between healthcare facilities.

Instead of depending entirely on an active internet connection:

```text
                    INTERNET AVAILABLE
                           │
                           ▼
┌──────────────┐    ┌───────────────┐    ┌───────────────┐
│     PHC      │───▶│  Sync Layer   │───▶│    Hospital   │
│              │    │               │    │               │
│ Create       │    │ Push / Pull   │    │ Receive       │
│ Referral     │    │ Synchronize   │    │ Review        │
└──────────────┘    └───────────────┘    └───────────────┘

                    INTERNET UNAVAILABLE
                           │
                           ▼

              ┌────────────────────────┐
              │ Local Device Storage   │
              │                        │
              │ Referral persists      │
              │ SyncQueue tracks work  │
              │ Retry when connected   │
              └────────────────────────┘
