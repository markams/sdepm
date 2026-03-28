<h1>API</h1>

In general, **keep the API as simple and concise as possible**.

*REST APIs are one of the most common kinds of web interfaces available today. Therefore, it's very important to design REST APIs properly so that we won't run into problems down the road.*

*Otherwise, we create problems for clients that use our APIs, which isn’t pleasant and detracts people from using our API.*

*If we don’t follow commonly accepted conventions, then we confuse the maintainers of the API and the clients that use them since it’s different from what everyone expects.*

https://stackoverflow.blog/2020/03/02/best-practices-for-rest-api-design/

---

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
