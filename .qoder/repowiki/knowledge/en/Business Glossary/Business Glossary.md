---
kind: business_term
name: Business Glossary
category: business_term
scope:
    - '**'
---

### Lida Value
- Definition：The in-app wallet feature whose balance can fund airtime/data purchases; separate from the mobile-money/card payment rails. SEND is a Lida Value menu action debited directly from this wallet, while USE is a purchase paid from the same balance with a shortfall path to Advansis Pay.
- Aliases：LV、Lida Wallet

### SEND
- Definition：A Lida Value menu action that moves value from the sender's Lida Value wallet to a recipient who receives airtime or data (not wallet value). It is debited from the Lida Value wallet and does not invoke the mobile-money or card payment flow.

### Auto Detect
- Definition：The default network-selection mode in the airtime/data wizards: the operator is inferred from the entered phone number (autodetect), with a Ghana-specific Prymo override. Users may still manually pick a network from the catalogue, which locks the choice for the rest of the run.
- Aliases：autodetect

### Ported-number sheet
- Definition：A confirmation prompt shown when a user selects Auto Detect and the detected operator differs from the number's original owner (ported number). It lets the user confirm or change the network before submitting.

### What's new
- Definition：The Play Console update message attached to a release bundle. Two variants are maintained: Message A (full feature release) and Message B (maintenance update), chosen based on whether the previous version is already on production.

### Upload keystore
- Definition：The signed `.jks` keystore (`lidapay-upload.jks`) used to sign Play releases; its SHA-256 must match the certificate registered in Play App Signing so Play accepts updates.
- Aliases：upload_cert
