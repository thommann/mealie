---
name: add-ts-api-class
description: "
  Scaffold a new TypeScript API class extending the correct BaseCRUDAPI tier, register it on UserApiClient
  or AdminAPI, and wire up the routes object.
  Use when adding a new backend domain that needs a frontend client.
  Do NOT use for modifying generated type files in frontend/app/lib/api/types/ (run regen-ts-types instead).
---

## Before You Start

Read these files:
- `frontend/app/lib/api/base/base-clients.ts` — `BaseAPI`, `BaseCRUDAPIReadOnly`, `BaseCRUDAPI` hierarchy
- `frontend/app/lib/api/user/organizer-categories.ts` — simplest complete CRUD example
- `frontend/app/lib/api/user/recipes/recipe.ts` — complex API with extra methods
- `frontend/app/lib/api/client-user.ts` — `UserApiClient` where you register new APIs
- `frontend/app/lib/api/base/route.ts` — `route()` URL builder function

## Step 1: Choose the correct base class

| Scenario | Extend |
|----------|--------|
| Full CRUD resource (POST/GET/PUT/DELETE) | `BaseCRUDAPI` |
| Read-only resource (GET only) | `BaseCRUDAPIReadOnly` |
| Action-only or mixed endpoints | `BaseAPI` |

## Step 2: Create the API class file

```typescript
// frontend/app/lib/api/user/{entity}.ts
import { BaseCRUDAPI } from '../base/base-clients';
import { route } from '../base';
import type { Create{Entity}, {Entity}Out, Update{Entity} } from '../types/{domain}';

const prefix = '/api';
const routes = {
  base: `${prefix}/{entities}`,
  item: (id: string) => `${prefix}/{entities}/${id}`,
  // Add domain-specific routes:
  bySlug: (slug: string) => `${prefix}/{entities}/slug/${slug}`,
  export: (id: string) => `${prefix}/{entities}/${id}/export`,
};

export class {Entity}API extends BaseCRUDAPI<Create{Entity}, {Entity}Out, Update{Entity}> {
  baseRoute = routes.base;
  itemRoute = routes.item;

  // Extra methods beyond standard CRUD:
  async getBySlug(slug: string) {
    return await this.requests.get<{Entity}Out>(routes.bySlug(slug));
  }

  // For paginated GET with filters:
  async getAll(params?: Record<string, unknown>) {
    return await this.requests.get<{Entity}Pagination>(route(routes.base, params ?? {}));
  }
}
```

**`data` is always `T | null`** — errors are never thrown:

```typescript
// At the call site, always check both:
const { data, error } = await api.{entities}.getOne(id);
if (error) {
  console.error('Failed:', error);
  return;
}
if (data) {
  // TypeScript still won't warn you — null-check anyway
  console.log(data.name);
}
```

## Step 3: Register on UserApiClient

```typescript
// frontend/app/lib/api/client-user.ts
import { {Entity}API } from './user/{entity}';

export class UserApiClient {
  // ... existing apis ...
  {entities}: {Entity}API;

  constructor(requests: ApiRequestInstance) {
    // ... existing assignments ...
    this.{entities} = new {Entity}API(requests);
    Object.freeze(this);  // this line already exists — add your assignment BEFORE it
  }
}
```

**`Object.freeze(this)` is called in the constructor.** Your property must be assigned before that line. `Object.freeze` means you cannot add properties at runtime — attempts silently fail in sloppy mode.

## Step 4: For admin-domain APIs, register on AdminAPI

```typescript
// frontend/app/lib/api/client-admin.ts
import { Admin{Entity}API } from './admin/admin-{entity}';

export class AdminAPI {
  {entities}: Admin{Entity}API;
  // ...
}
```

## Step 5: Use the API in components

```typescript
// In <script setup lang="ts">
// Call useUserApi() ONCE at setup time — never inside event handlers or loops
const api = useUserApi();

async function load() {
  const { data, error } = await api.{entities}.getAll();
  if (data) items.value = data.items;
}
```

## Verify

```bash
cd frontend
yarn lint --max-warnings=0 app/lib/api/user/{entity}.ts
yarn test:ci
```

## Common Mistakes

1. **Using `duplicateOne()` on non-recipe resources**: `BaseCRUDAPI.duplicateOne()` is hardcoded to return `Recipe` type. Do not call it from non-recipe API classes.
2. **Calling `useUserApi()` inside event handlers**: Each call creates a new class instance with all sub-APIs. Cache the result in a `const` at component setup time.
3. **`route()` with absolute URLs**: `route('/api/...', params)` works; `route('https://...', params)` breaks the internal URL stripping logic.
4. **Inconsistent class suffix casing**: Existing classes mix `API` and `Api` suffixes. New classes should use `Api` (lowercase i) per the most recent convention.
