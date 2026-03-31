# @fyno/react-native-totp

## Overview

Time-based One-Time Password (TOTP) is a secure authentication mechanism used as part of multi-factor authentication (MFA). It generates a temporary, one-time password based on a shared secret and the current time. Each OTP is valid only for a short duration, reducing the risk of replay attacks and unauthorized access. Refer [Fyno TOTP](https://fyno.io/docs/verification) for more information.

---

## Installation

```sh
npm install @fyno/react-native-totp
```

or

```sh
yarn add @fyno/react-native-totp
```

---

## Usage

```js
import {
  initFynoConfig,
  registerTenant,
  setConfig,
  getTotp,
} from '@fyno/react-native-totp';
```

### Initialize Configuration

```js
initFynoConfig(wsid, distinctId);
```

Initializes the SDK with your workspace configuration.

- **wsid**: Workspace ID
- **distinctId**: Unique identifier for the current user/session

This must be called before using any other methods.

### Register a Tenant

```js
registerTenant(tenantId, tenantName, totpToken);
```

Registers a tenant for TOTP generation.

- **tenantId**: Unique identifier for the tenant
- **tenantName**: Human-readable name for the tenant
- **totpToken**: Token received from the below API endpoint. Ensure the token is securely transmitted and stored, as it is used to generate OTPs.

```js
/${wsid}/totp/${tenantId}/register
```

### Configure TOTP Settings

```js
setConfig(tenantId, {
  digits: digits,
  period: period,
  algorithm: algorithm,
});
```

Sets the TOTP configuration for a tenant.

- **digits**: Number of digits in the OTP (6–9)
- **period**: Time validity of each OTP (in seconds)
  - Allowed values: 15, 30, 45, 60, 120, 180, 240, 300
- **algorithm**: Hashing algorithm used
  - Allowed values: SHA1, SHA256, SHA512

### Generate TOTP

```js
getTotp(tenantId);
```

Generates the current TOTP for the given tenant.

- Returns a time-based OTP valid for the configured period
- Should be used before expiry
- OTP reuse is prohibited

### Delete Tenant

```js
deleteTenant(tenantId);
```

Removes a tenant and its associated TOTP configuration.

- This action is irreversible
- All stored secrets and configurations for the tenant will be deleted

---

## License

- [MIT](LICENSE)
