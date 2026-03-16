<h1>Listing and Activity</h1>

**Status: PROPOSAL**

Context: https://github.com/SEMICeu/sdep/issues/39 (random checks).

Although for random checks only listings apply, this document covers both listings and activities, to understand the whole picture.

- [Definitions](#definitions)
  - [Listing](#listing)
  - [Activity](#activity)
  - [Address](#address)
  - [Area](#area)
  - [Regulated area](#regulated-area)
- [Listing regulation](#listing-regulation)
  - [Registration](#registration)
  - [Reporting](#reporting)
  - [Enforcement](#enforcement)
  - [Monitoring](#monitoring)
- [Activity regulation](#activity-regulation)
  - [Reporting](#reporting-1)
  - [Enforcement](#enforcement-1)
  - [Monitoring](#monitoring-1)
- [Design notes](#design-notes)
  - [RG adress](#rg-adress)
  - [Asynchronous](#asynchronous)
  - [Area - CA - RG](#area-ca-rg)
  - [Unit](#unit)

<div style="page-break-after: always"></div>

## Definitions

### Listing

A property that is available for letting on a short-term rental platform (**STR**).

### Activity

Renting data for a property that is actually let on a short-term rental platform (**STR**).

### Address

The physical location of a property, in the context of a listing or activity.

### Area

The geographical zone in which an address is located, in the context of a listing or activity.

### Regulated area

An area that is subject to Regulation (EU) 2024/1028.

https://eur-lex.europa.eu/eli/reg/2024/1028/oj/eng

<div style="page-break-after: always"></div>

## Listing regulation

If a listing address is located within a regulated area, listing regulation applies.

The main regulatory functions are:

- Registration
- Reporting
- Enforcement
- Monitoring

### Registration

If a listing address is located within a regulated area, the listing host must get a registration number (**reg#**) for the listing address in a registration registry (**RG**).

This process is outside the scope of **SDEP**.

### Reporting

From listing addresses within regulated areas, an **STR** selects a random set and performs actions. This process is referred to as **random checks**

**European Commission prerequisite:** The evaluation process described below is the responsibility of STR platforms, not SDEP.

The table below illustrates the process.

| STR: has listing an STR reg# | Step | Who  | Action                                                                                            | Flag           |
| ---------------------------- | ---- | ---- | ------------------------------------------------------------------------------------------------- | -------------- |
| Yes                          | 1    | STR  | POST the **reg#** and `areaId` of the listing address to **SDEP**                                 |                |
|                              | 2a   | SDEP | Determine the **reg#** status: OK (present and active in RG), NOK (unkown or expired in RG)       |                |
|                              | 2b   | SDEP | Determine the **reg#** address as registered in the **RG**                                        |                |
|                              | 3    | STR  | GET the **reg#** status and the **RG address** from **SDEP**                                      |                |
|                              | 4    | STR  | Evaluate the returned results                                                                     |                |
|                              | 4a   | STR  | If the **reg#** is Unknown in RG, POST a flagged listing to **SDEP**                              | **RG-UNK**     |
|                              | 4b   | STR  | If the **reg#** is Expired in RG, POST a flagged listing to **SDEP**                              | **RG-EXP**     |
|                              | 4c   | STR  | If the **STR address** and the **RG address** have a Mismatch, POST a flagged listing to **SDEP** | **STR-RG-MSM** |
| No                           | 5a   | STR  | Detect the non-available **reg#** through an internal check                                       |                |
|                              | 5b   | STR  | POST a flagged listing to **SDEP**                                                                | **STR-NAV**    |

To conclude, the STR thus covers the following checks and reporting:

- **Existence**: whether the **reg#** provided by the **STR** is known in the **RG** (RG-UNK)
- **Validity**: whether the **reg#** in the **RG** is active and not expired (RG-EXP)
- **Correctness**: whether, for a given **reg#**, the **STR** address matches the **RG** address (STR-RG-MSM)
- **Completeness**: whether a **reg#** is defined in the **STR** (STR-NAV)

### Enforcement

An **STR** informs the listing owner (host) when any of the above flags applies.

A **CA** retrieves flagged listings from SDEP in order to enforce regulation.

This enforcement process is outside the scope of SDEP.

### Monitoring

A **listing monitoring authority** (**LMA**) determines whether an **STR** complies with listing regulation.

Minimum information required:

- The number of flagged listings for the **STR**, as available from **SDEP**

Additional information may be required, depending on the **LMA**.

For example, an **LMA** may need to determine whether the random selection was in fact random.

In the Netherlands, the **LMA** is the Autoriteit Consument & Markt (**ACM**).

<div style="page-break-after: always"></div>

## Activity regulation

If an activity address is located within a regulated area, activity regulation applies.

The main regulatory functions are:

- Reporting
- Enforcement
- Monitoring

### Reporting

An **STR** processes all activities and performs actions based on the activity address.

The table below illustrates the reporting process.

| Activity in area | Action                                                                         |
| ---------------- | ------------------------------------------------------------------------------ |
| Yes              | **STR** POSTs the activity to **SDEP**                                         |
| No               | **STR** detects this internally; the activity is outside the scope of **SDEP** |

### Enforcement

A **Competent Authority** (**CA**) retrieves activities from **SDEP** in order to enforce regulation.

The enforcement process is outside the scope of **SDEP**. For example, CA may assess whether the number of activities is less than or equal to the maximum number of allowed lettings within a given period.

### Monitoring

An **activity monitoring authority** (**AMA**) determines whether an **STR** complies with activity regulation.

Minimum information required:

- The number of activities for the **STR**, as available from **SDEP**

Additional information may be required, depending on the **AMA**.

In The Netherlands, the **AMA** is the Inspectie Leefomgeving en Transport (**ILT**).

<div style="page-break-after: always"></div>

## Design notes

### RG adress

On returning the RG adress.

**Prerequisite:** Integration partners (**STR platforms** and **Competent Authorities (CA)**) are trusted entities.

- This trust may be established through a **separate identification process** (e.g., national coordination mechanisms)
- Cf. the process for acquiring **organization-validated certificates** from a trusted service provider

**Address fields:** All address fields are optional to remain **member-state agnostic**.

- Each Member State decides how a platform can **match the STR-provided address with the RG address**.
- For example, in Belgium, a single **postal code may correspond to multiple addresses**.

**Rejected approach:** Returning an **address hash** instead of the full address data (based on the security principle *“need to know”*)

- **Limited security benefit:** A malicious STR could still derive the **registration number / RG address** by hashing all publicly available addresses
- **Error-prone:** Minor formatting differences may result in different hashes (e.g., `"Example Street"` vs. `"Example St."`)
- **Operational overhead:** It would introduce additional **key management and maintenance complexity**

### Asynchronous

The interaction between **STR**, **SDEP**, and **RG** will be asynchronous.

- To exchange areas (already implemented)
- To exchange activities (already implemented)
- To exchange listings (to be implemented)

Motivation:

- An **STR** does not need an immediate, synchronous response to a **reg#** or address-hash query
- Both **STR** and **RG** can invoke **SDEP**, without requiring asynchronous callback flows in the other direction
- **SDEP** does not need to manage **RG** unavailability or maintain a retry or catch-up queue
- **SDEP** does not need to know how many **RGs** exist or maintain many point-to-point connections
- **SDEP** does not need to know whether a given **RG** exposes an API
- Reducing these dependencies lowers implementation risk
- This approach is agnostic to individual EU Member State implementations

### Area - CA - RG

In the internal datamodel, a mapping from **Area => CA => RG** will be defined.

So, for a given **STR reg#** and STR-adress (located in/represented by `areaId`), it is known which **CA** and **RG** govern that **reg#**.

### Unit

There is no need for a separate “unit” in the data model.

For example, where one address contains multiple units, such as one address with two rooms, this results in:

- 1x **reg#**
- 2x listing, each with its own unique functional identifier
- 2x activity, each with its own unique functional identifier

Enforcement by a **CA** can still take place at address level.
