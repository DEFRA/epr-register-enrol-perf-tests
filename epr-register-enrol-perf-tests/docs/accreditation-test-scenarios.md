# Test Scenarios: Routing to the Right Environment Agency / Nation

---

## Reprocessors — Happy path: Reprocessor submits an accreditation application

---

**TC-R01 · England · Steel · Up to 500 tonnes**

| Step | |
|------|-|
| **Given** | I am a Reprocessor operator based in England |
| **And** | I am logged in using my Defra ID for the organisation |
| **And** | I select Steel as the material for my accreditation submission |
| **And** | I complete PRN Tonnage (Up to 500 tonnes), Business Plan, Business Plan Details, and Sampling and Inspection Plan |
| **When** | I submit the application successfully |
| **Then** | I receive an application reference number |
| **And** | I see the payment amount appropriate for Up to 500 tonnes |
| **And** | A confirmation email is sent to the operator |
| **Pass / Fail** | |
| **Comments** | |

---

**TC-R02 · Wales · Paper · Up to 1000 tonnes**

| Step | |
|------|-|
| **Given** | I am a Reprocessor operator based in Wales |
| **And** | I am logged in using my Defra ID for the organisation |
| **And** | I select Paper as the material for my accreditation submission |
| **And** | I complete PRN Tonnage (Up to 1000 tonnes), Business Plan, Business Plan Details, and Sampling and Inspection Plan |
| **When** | I submit the application successfully |
| **Then** | I receive an application reference number |
| **And** | I see the payment amount appropriate for Up to 1000 tonnes |
| **And** | A confirmation email is sent to the operator |
| **Pass / Fail** | |
| **Comments** | |

---

**TC-R03 · Northern Ireland · Glass remelt · Up to 10000 tonnes**

| Step | |
|------|-|
| **Given** | I am a Reprocessor operator based in Northern Ireland |
| **And** | I am logged in using my Defra ID for the organisation |
| **And** | I select Glass remelt as the material for my accreditation submission |
| **And** | I complete PRN Tonnage (Up to 10000 tonnes), Business Plan, Business Plan Details, and Sampling and Inspection Plan |
| **When** | I submit the application successfully |
| **Then** | I receive an application reference number |
| **And** | I see the payment amount appropriate for Up to 10000 tonnes |
| **And** | A confirmation email is sent to the operator |
| **Pass / Fail** | |
| **Comments** | |

---

**TC-R04 · Scotland · Aluminium · Over 10000 tonnes**

| Step | |
|------|-|
| **Given** | I am a Reprocessor operator based in Scotland |
| **And** | I am logged in using my Defra ID for the organisation |
| **And** | I select Aluminium as the material for my accreditation submission |
| **And** | I complete PRN Tonnage (Over 10000 tonnes), Business Plan, Business Plan Details, and Sampling and Inspection Plan |
| **When** | I submit the application successfully |
| **Then** | I receive an application reference number |
| **And** | I see the payment amount appropriate for Over 10000 tonnes |
| **And** | A confirmation email is sent to the operator |
| **Pass / Fail** | |
| **Comments** | |

---

## Reprocessors — Unhappy path: Operator withdraws a submitted application

---

**TC-W01 · Reprocessor · England · Steel · Up to 500 tonnes**

| Step | |
|------|-|
| **Given** | I am a Reprocessor operator based in England |
| **And** | I am logged in using my Defra ID for the organisation |
| **And** | I select Steel as the material for my accreditation submission |
| **And** | I have completed all accreditation tasks for Up to 500 tonnes |
| **And** | I have submitted the application successfully |
| **When** | I withdraw the submitted application |
| **Then** | The application status is set to "Withdrawn" |
| **And** | A withdrawal notification email is sent to the England regulator |
| **Pass / Fail** | |
| **Comments** | |

---

**TC-W02 · Exporter · Wales · Plastics · Over 10000 tonnes**

| Step | |
|------|-|
| **Given** | I am an Exporter operator based in Wales |
| **And** | I am logged in using my Defra ID for the organisation |
| **And** | I select Plastics as the material for my accreditation submission |
| **And** | I have completed all accreditation tasks for Over 10000 tonnes |
| **And** | I have submitted the application successfully |
| **When** | I withdraw the submitted application |
| **Then** | The application status is set to "Withdrawn" |
| **And** | A withdrawal confirmation email is sent to the operator |
| **And** | A withdrawal notification email is sent to the Wales regulator |
| **Pass / Fail** | |
| **Comments** | |

---

## Exporters — Happy path: Exporter adds new overseas sites

---

**TC-E01 · England · Steel · Up to 500 tonnes · EU with OECD**

| Step | |
|------|-|
| **Given** | I am an Exporter operator based in England |
| **And** | I am logged in using my Defra ID for the organisation |
| **And** | I select Steel as the material for my accreditation submission |
| **And** | I complete PRN Tonnage (Up to 500 tonnes), Business Plan, Business Plan Details, and Sampling and Inspection Plan |
| **And** | I add new overseas reprocessing sites located in EU with OECD |
| **And** | I upload BES evidence where required for each site |
| **When** | I submit the application successfully |
| **Then** | I receive an application reference number |
| **And** | I see the payment amount appropriate for Up to 500 tonnes |
| **And** | A confirmation email is sent to the operator |
| **Pass / Fail** | |
| **Comments** | |

---

**TC-E02 · Wales · Paper · Up to 1000 tonnes · EU, Vietnam**

| Step | |
|------|-|
| **Given** | I am an Exporter operator based in Wales |
| **And** | I am logged in using my Defra ID for the organisation |
| **And** | I select Paper as the material for my accreditation submission |
| **And** | I complete PRN Tonnage (Up to 1000 tonnes), Business Plan, Business Plan Details, and Sampling and Inspection Plan |
| **And** | I add new overseas reprocessing sites located in EU and Vietnam |
| **And** | I upload BES evidence where required for each site |
| **When** | I submit the application successfully |
| **Then** | I receive an application reference number |
| **And** | I see the payment amount appropriate for Up to 1000 tonnes |
| **And** | A confirmation email is sent to the operator |
| **Pass / Fail** | |
| **Comments** | |

---

**TC-E03 · Northern Ireland · Glass remelt · Up to 10000 tonnes · EU, Japan**

| Step | |
|------|-|
| **Given** | I am an Exporter operator based in Northern Ireland |
| **And** | I am logged in using my Defra ID for the organisation |
| **And** | I select Glass remelt as the material for my accreditation submission |
| **And** | I complete PRN Tonnage (Up to 10000 tonnes), Business Plan, Business Plan Details, and Sampling and Inspection Plan |
| **And** | I add new overseas reprocessing sites located in EU and Japan |
| **And** | I upload BES evidence where required for each site |
| **When** | I submit the application successfully |
| **Then** | I receive an application reference number |
| **And** | I see the payment amount appropriate for Up to 10000 tonnes |
| **And** | A confirmation email is sent to the operator |
| **Pass / Fail** | |
| **Comments** | |

---

**TC-E04 · Scotland · Aluminium · Over 10000 tonnes · EU with OECD (Lagos)**

| Step | |
|------|-|
| **Given** | I am an Exporter operator based in Scotland |
| **And** | I am logged in using my Defra ID for the organisation |
| **And** | I select Aluminium as the material for my accreditation submission |
| **And** | I complete PRN Tonnage (Over 10000 tonnes), Business Plan, Business Plan Details, and Sampling and Inspection Plan |
| **And** | I add new overseas reprocessing sites located in EU with OECD (Lagos) |
| **And** | I upload BES evidence where required for each site |
| **When** | I submit the application successfully |
| **Then** | I receive an application reference number |
| **And** | I see the payment amount appropriate for Over 10000 tonnes |
| **And** | A confirmation email is sent to the operator |
| **Pass / Fail** | |
| **Comments** | |

---

## Exporters — Happy path: Exporter selects existing overseas sites

---

**TC-ES01 · England · Steel · Up to 500 tonnes · EU with OECD + Vietnam**

| Step | |
|------|-|
| **Given** | I am an Exporter operator based in England |
| **And** | I am logged in using my Defra ID for the organisation |
| **And** | I select Steel as the material for my accreditation submission |
| **And** | I complete PRN Tonnage (Up to 500 tonnes), Business Plan, Business Plan Details, and Sampling and Inspection Plan |
| **And** | I select an existing overseas reprocessing site in EU with OECD and an existing site in Vietnam |
| **And** | I upload BES evidence for the Vietnam site (outside EU/OECD) |
| **When** | I submit the application successfully |
| **Then** | I receive an application reference number |
| **And** | I see the payment amount appropriate for Up to 500 tonnes |
| **And** | A confirmation email is sent to the operator |
| **Pass / Fail** | |
| **Comments** | |

---

**TC-ES02 · England · Steel · Up to 500 tonnes · EU with OECD + Japan**

| Step | |
|------|-|
| **Given** | I am an Exporter operator based in England |
| **And** | I am logged in using my Defra ID for the organisation |
| **And** | I select Steel as the material for my accreditation submission |
| **And** | I complete PRN Tonnage (Up to 500 tonnes), Business Plan, Business Plan Details, and Sampling and Inspection Plan |
| **And** | I select an existing overseas reprocessing site in EU with OECD and an existing site in Japan |
| **And** | I upload BES evidence for the Japan site (outside EU/OECD) |
| **When** | I submit the application successfully |
| **Then** | I receive an application reference number |
| **And** | I see the payment amount appropriate for Up to 500 tonnes |
| **And** | A confirmation email is sent to the operator |
| **Pass / Fail** | |
| **Comments** | |

---

## Regulator — Grants an accreditation application

---

**TC-REG01 · Exporter application**

| Step | |
|------|-|
| **Given** | I am logged in as a regulator using my Entra ID |
| **And** | I am assigned an accreditation application for an Exporter |
| **And** | I have validated all application details including all uploaded files |
| **When** | I complete all review tasks and approve the application |
| **Then** | The application status is set to "Granted" |
| **And** | An approval confirmation email is sent to the operator |
| **Pass / Fail** | |
| **Comments** | |

---

**TC-REG02 · Reprocessor application**

| Step | |
|------|-|
| **Given** | I am logged in as a regulator using my Entra ID |
| **And** | I am assigned an accreditation application for a Reprocessor |
| **And** | I have validated all application details including all uploaded files |
| **When** | I complete all review tasks and approve the application |
| **Then** | The application status is set to "Granted" |
| **And** | An approval confirmation email is sent to the operator |
| **Pass / Fail** | |
| **Comments** | |

---

## Regulator — Refuses an accreditation application

---

**TC-REG03 · Exporter application**

| Step | |
|------|-|
| **Given** | I am logged in as a regulator using my Entra ID |
| **And** | I am assigned an accreditation application for an Exporter |
| **And** | I have reviewed the application details including all uploaded files |
| **And** | I have identified reasons to refuse the application |
| **When** | I complete all review tasks and refuse the application with a reason |
| **Then** | The application status is set to "Refused" |
| **And** | A refusal notification email is sent to the operator stating the reason |
| **Pass / Fail** | |
| **Comments** | |

---

**TC-REG04 · Reprocessor application**

| Step | |
|------|-|
| **Given** | I am logged in as a regulator using my Entra ID |
| **And** | I am assigned an accreditation application for a Reprocessor |
| **And** | I have reviewed the application details including all uploaded files |
| **And** | I have identified reasons to refuse the application |
| **When** | I complete all review tasks and refuse the application with a reason |
| **Then** | The application status is set to "Refused" |
| **And** | A refusal notification email is sent to the operator stating the reason |
| **Pass / Fail** | |
| **Comments** | |

---

## Regulator — Sends a query on an accreditation application

---

**TC-REG05 · Exporter application**

| Step | |
|------|-|
| **Given** | I am logged in as a regulator using my Entra ID |
| **And** | I am assigned an accreditation application for an Exporter |
| **And** | I have reviewed the application details including all uploaded files |
| **And** | I have queries to raise on the application covering areas such as PRN Tonnage, Business Plan, etc. |
| **When** | I send the query with all messages to the operator |
| **Then** | The application status is set to "Queried" |
| **And** | A query notification email is sent to the operator including the query message |
| **Pass / Fail** | |
| **Comments** | |

---

**TC-REG06 · Reprocessor application**

| Step | |
|------|-|
| **Given** | I am logged in as a regulator using my Entra ID |
| **And** | I am assigned an accreditation application for a Reprocessor |
| **And** | I have reviewed the application details including all uploaded files |
| **And** | I have queries to raise on the application covering areas such as PRN Tonnage, Business Plan, etc. |
| **When** | I send the query with all messages to the operator |
| **Then** | The application status is set to "Queried" |
| **And** | A query notification email is sent to the operator including the query message |
| **Pass / Fail** | |
| **Comments** | |

---

## Operator — Updates an application in Queried state

---

**TC-REG07 · Exporter application**

| Step | |
|------|-|
| **Given** | I am an Exporter operator logged in using my Defra ID |
| **And** | I have an accreditation application that is in "Queried" state |
| **And** | I can see the query message sent by the regulator |
| **When** | I update the application on the required tasks identified in the query |
| **Then** | The application status is set to "Updated" |
| **And** | The regulator can review the updated application and proceed to approval or refusal |
| **Pass / Fail** | |
| **Comments** | |

---

**TC-REG08 · Reprocessor application**

| Step | |
|------|-|
| **Given** | I am a Reprocessor operator logged in using my Defra ID |
| **And** | I have an accreditation application that is in "Queried" state |
| **And** | I can see the query message sent by the regulator |
| **When** | I update the application on the required tasks identified in the query |
| **Then** | The application status is set to "Updated" |
| **And** | The regulator can review the updated application and proceed to approval or refusal |
| **Pass / Fail** | |
| **Comments** | |
