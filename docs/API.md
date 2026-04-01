<h1>API</h1>

This document describes principles and patterns for the SDEP API.

Table of contents

- [Principle](#principle)
- [Patterns](#patterns)
- [HTTP status codes](#http-status-codes)
  - [Success](#success)
  - [Client errors](#client-errors)
  - [Server errors](#server-errors)
- [API Gateway?](#api-gateway)
  - [Motivation](#motivation)
  - [When to Add a Dedicated API Gateway](#when-to-add-a-dedicated-api-gateway)
  - [Bottom Line](#bottom-line)
- [API Gateway?](#api-gateway-1)
  - [Motivation](#motivation-1)
  - [When](#when)
  - [Conclusion](#conclusion)

## Principle

**Keep the API as simple and concise as possible.**

> REST APIs are one of the most common kinds of web interfaces available today. \
> Therefore, it's very important to design REST APIs properly so that we won't run into problems down the road. \
> Otherwise, we create problems for clients that use our APIs, which isn’t pleasant and detracts people from using our API. \
> If we don’t follow commonly accepted conventions, then we confuse the maintainers of the API and the clients that use them since it’s different from what everyone expects.

---

*https://stackoverflow.blog/2020/03/02/best-practices-for-rest-api-design/*

## Patterns

| #                | Decision                                           | Motivation/example                                                                                                            |
| :--------------- | :------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------- |
| **API&nbsp;01**  | Support OpenAPI 3.1.0                              | Swagger 2.0 is legacy - https://swagger.io/specification/                                                                     |
| **API&nbsp;02**  | All endpoints are self-explanatory/well-documented |                                                                                                                               |
| **API&nbsp;03**  | Use nouns instead of verbs                         | Best practice - https://logius-standaarden.github.io/API-Design-Rules/                                                        |
| **API&nbsp;04**  | Use plurals for resources that affect collections  | Best practice - https://logius-standaarden.github.io/API-Design-Rules/                                                        |
| **API&nbsp;05**  | Consistent datamodel                               | Avoid code duplication, only have `Activity`, `Area`, consider adding an attribute to indicate "non-reporting records" for CA |
| **API&nbsp;06**  | Consistent endpoints                               | Have POST/GET "mirrors": `POST /ca/areas`, `GET /str/areas`; `POST /str/activities`, `GET /ca/activities`                     |
| **API&nbsp;07**  | Consistent pagination                              | Have `offset` and `limit` for all endpoints with (potential) many records                                                     |
| **API&nbsp;08**  | Syntax validation                                  | Example: `postal code`                                                                                                        |
| **API&nbsp;09**  | Semantical validation                              | Example: `begin timestamp < end timestamp`                                                                                    |
| **API&nbsp;10**  | Integrity validation                               | Example: can only submit activities for existing areas                                                                        |
| **API&nbsp;11**  | Single record POST (default)                       | To avoid transaction performance issues and to keep the endpoints simple (as opposed to bulk updates)                         |
| **API&nbsp;11b** | Bulk POST (complement)                             | For high-volume STR platforms; available at `/str/activities/bulk`                                                            |
| **API&nbsp;12**  | Logical ordering => readability                    | For POST, request and response follow the same ordering, extra data in response is moved to the end                           |
| **API&nbsp;13**  | Essentiality                                       | Example: in POST activities, only `areaId` and `competentAuthorityId`, but no `competentAuthorityName`                        |
| **API&nbsp;14**  | Essentiality/security                              | Example: in POST activities request, no need to include `platformId`                                                          |
| **API&nbsp;15**  | Consistent HTTP response codes                     | See [HTTP status codes](#http-status-codes) below                                                                             |
| **API&nbsp;16**  | STR and CA: manage area change                     | Areas may change over time, SDEP only administrates the changes and exposes the latest "truth"                                |

---

## HTTP status codes

### Success

| HTTP Status | Meaning    | When                                                               |
| ----------- | ---------- | ------------------------------------------------------------------ |
| 200         | OK         | GET request completed successfully; bulk POST with partial success |
| 201         | Created    | POST request created a new resource                                |
| 204         | No Content | DELETE request completed successfully (e.g. deactivate area)       |

### Client errors

| HTTP Status | Meaning               | When                                                                                                                          |
| ----------- | --------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| 400         | Bad Request           | Invalid query parameters on a GET request (e.g. `offset=-1` or `limit=abc`), or missing client credentials                    |
| 401         | Unauthorized          | Missing, invalid, or expired authentication token; missing required token claims (`client_id`, `client_name`)                 |
| 403         | Forbidden             | Authenticated but missing a required role (`sdep_ca`, `sdep_str`, `sdep_read`, `sdep_write`)                                  |
| 404         | Not Found             | Requested resource does not exist, is unavailable, or has been deleted                                                        |
| 409         | Conflict              | Duplicate resource (unique constraint violation)                                                                              |
| 422         | Unprocessable Content | Invalid request body on a POST request (e.g. missing required field), or business rule violation (e.g. start time > end time) |

### Server errors

| HTTP Status | Meaning               | When                                                                   |
| ----------- | --------------------- | ---------------------------------------------------------------------- |
| 500         | Internal Server Error | Unexpected condition that prevented fulfilling the request (catch-all) |
| 503         | Service Unavailable   | Database or authorization server (Keycloak) temporarily unavailable    |

For the mapping between application exceptions and HTTP status codes, see [Exception Handling](ARCHITECTURE_TECH.md#exception-handling) in the Architecture document.

## API Gateway?

For production use in your own country, the utilization of a separate API gateway can be considered (on top of the SDEP API).

In SDEP-NL, a separate API gateway it not utlized right now, unless there are concrete edge-control requirements that cannot be handled by the existing ingress/reverse proxy setup.

### Motivation

- The API already acts as a functional gateway for data exchange (clear boundaries, OAuth2 client credentials, and role separation between `str` and `ca`).
- The exposed endpoints are mainly transactional (`POST /str/activities`, bulk ingest, area upload/download), so common gateway benefits like response caching are limited.
- Adding another gateway layer introduces additional complexity: extra latency, policy duplication risk, configuration drift, and another operational failure domain.
- A simpler and stronger baseline is one hardened edge (load balancer/ingress + WAF + TLS termination), with authorization and business rules enforced in the app and identity provider.

### When to Add a Dedicated API Gateway

Introduce one when at least one of these becomes a real requirement:

1. Per-client quota/rate limiting and burst controls at larger platform scale.
2. Centralized security/policy enforcement across multiple backend services (JWT claim rules, IP allowlists, mTLS, schema checks).
3. API product capabilities (developer portal, key lifecycle, detailed usage analytics by client, monetization).
4. Multi-service backend exposure with a single stable external contract.

### Bottom Line

No by default; yes conditionally.

Use architectural simplicity until specific non-functional requirements justify the additional gateway layer.

## API Gateway?

For production use in your own country, the utilization of a separate API gateway can be considered (on top of the SDEP API).

Within **SDEP NL**, a dedicated API gateway is currently **not** used. This is a deliberate choice based on how the platform is designed and operated. Only when specific edge-control requirements arise that cannot be handled by the existing ingress/reverse proxy setup should an additional gateway be introduced.

### Motivation

In context of SDEP NL:

- **SDEP NL already provides clear API boundaries** \
  The SDEP API itself acts as a functional gateway for data exchange, with well-defined domains (`str` vs `ca`), OAuth2 client credential flows, and strict role separation.

- **Workload is primarily transactional, not cache-driven** \
  Typical interactions (e.g. `POST /str/activities`, bulk ingestion, area upload/download) are write-heavy or data-exchange oriented, limiting the value of traditional API gateway features like response caching.

- **Existing edge setup is sufficient and controlled** \
  A hardened edge (ingress/reverse proxy + TLS termination) already provides the necessary entry point security and routing without introducing additional layers.

- **Operational simplicity is a key design principle** \
  Avoiding an extra gateway reduces:
  - latency in the request path
  - duplication of security and routing policies
  - risk of configuration drift
  - an additional operational and failure domain

- **Authorization is intentionally handled at the right layers** \
  Identity and access control are enforced via the identity provider and the application itself, aligning with SDEP’s architecture rather than shifting logic to an external gateway.

### When

Introducing a gateway could become relevant when concrete needs arise, such as:

1. Platform-scale **rate limiting or quota management per client**
2. Need for **API product capabilities** (developer portal, client onboarding, usage analytics)

### Conclusion

SDEP NL prioritizes a **simple, robust edge architecture**. A dedicated API gateway should only be introduced when clear non-functional requirements outweigh the added complexity.