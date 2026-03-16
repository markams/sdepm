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
  - [Supervision](#supervision)
- [Activity regulation](#activity-regulation)
  - [Reporting](#reporting-1)
  - [Enforcement](#enforcement-1)
  - [Supervision](#supervision-1)
- [Design notes](#design-notes)
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
- Supervision

### Registration

The listing address must be assigned a registration number (**reg#**) in a registration registry (**RG**).

This process is outside the scope of **SDEP**.

### Reporting

An **STR** randomly selects a set of listings, checks the listing address and **reg#**, performs the required actions, and reports the results. This process is referred to as **random checks**.

Reporting covers the following checks:

- **Completeness**: whether a **reg#** is defined in the **STR**
- **Existence**: whether the **reg#** provided by the **STR** exists in the **RG**
- **Validity**: whether the **reg#** in the **RG** is active and not expired
- **Correctness**: whether, for a given **reg#**, the **RG** address matches the **STR** address

The table below illustrates the reporting process.

| Listing in Area | Has reg# | Step | Who  | Action                                                                                                 | Flag        |
| --------------- | -------- | ---- | ---- | ------------------------------------------------------------------------------------------------------ | ----------- |
| Yes             | Yes      | 1    | STR  | POST the **reg#** and `areaId` of the listing address to **SDEP**                                      |             |
|                 |          | 2a   | SDEP | Determine the **reg#** status: OK / Missing in RG / Expired in RG                                      |             |
|                 |          | 2b   | SDEP | Map the **reg#** to a **RG address-hash** (that is, the address as registered in the **RG**)           |             |
|                 |          | 3    | STR  | GET the **reg#** status and **RG address-hash** from **SDEP**                                          |             |
|                 |          | 4    | STR  | Evaluate the returned results                                                                          |             |
|                 |          | 4a   | STR  | If the **reg#** is Missing in RG, POST a flagged listing to **SDEP**                                   | **MIS-RG**  |
|                 |          | 4b   | STR  | If the **reg#** is Expired in RG, POST a flagged listing to **SDEP**                                   | **EXP-RG**  |
|                 |          | 4c   | STR  | If the **RG address-hash** does not match the **STR address-hash**, POST a flagged listing to **SDEP** | **MISMA**    |
| Yes             | No       | 5a   | STR  | Detect a missing **reg#** through an internal check                                                    |             |
|                 |          | 5b   | STR  | If the **reg#** is missing in the **STR**, POST a flagged listing to **SDEP**                          | **MIS-STR** |
| No              | Yes      | 6    | STR  | Detect through an internal check that the listing is outside the scope of **SDEP**                     |             |
| No              | No       | 7    | STR  | Detect through an internal check that the listing is outside the scope of **SDEP**                     |             |

The address match uses an address-hash rather than the full address data, based on the security principle of “need to know”.

### Enforcement

An **STR** informs the listing owner (host) when any of the above flags applies.

### Supervision

A **listing supervisor** (**LSR**) determines whether an **STR** complies with listing regulation.

Minimum information required:

- The number of flagged listings for the **STR**, as available from **SDEP**

Additional information may be required, depending on the **LSR**.

For example, an **LSR** may need to determine whether the random selection was in fact random.

In the Netherlands, the **LSR** is the Autoriteit Consument & Markt (**ACM**).

<div style="page-break-after: always"></div>

## Activity regulation

If an activity address is located within a regulated area, activity regulation applies.

The main regulatory functions are:

- Reporting
- Enforcement
- Supervision

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

### Supervision

An **activity supervisor** (**ASR**) determines whether an **STR** complies with activity regulation.

Minimum information required:

- The number of activities for the **STR**, as available from **SDEP**

Additional information may be required, depending on the **ASR**.

In The Netherlands, the **ASR** is the Inspectie Leefomgeving en Transport (**ILT**).

<div style="page-break-after: always"></div>

## Design notes

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
