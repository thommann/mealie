# frontend/app/lib/api/ — Typed API Client Layer

Hand-written TypeScript classes wrapping all Mealie backend endpoints. Three client tiers: user (authenticated), admin, and public. All errors are returned in `RequestResponse<T>`, never thrown.

## Class Hierarchy

```
BaseAPI
├── BaseCRUDAPIReadOnly<ReadType>
│   └── BaseCRUDAPI<CreateType, ReadType, UpdateType=CreateType>
│       ├── RecipeAPI (+ nested CommentsApi, RecipeShareApi)
│       ├── CategoriesAPI
│       └── ... (every domain entity)
├── AdminUsersApi (direct BaseAPI extension)
└── ...
```

## Picking the Right Base Class

| Scenario | Extend |
|----------|--------|
| Full CRUD resource | `BaseCRUDAPI<C, R, U>` |
| Read-only resource | `BaseCRUDAPIReadOnly<R>` |
| Action-only / mixed | `BaseAPI` with explicit methods |

## Defining a New API Class

```typescript
import { BaseCRUDAPI } from '../base/base-clients'
import type { MyCreate, MyRead, MyUpdate } from '../types/my-domain'

const prefix = '/api'
const routes = {
  base: `${prefix}/my-entities`,
  item: (id: string) => `${prefix}/my-entities/${id}`,
  // Add domain-specific routes:
  bySlug: (slug: string) => `${prefix}/my-entities/slug/${slug}`,
}

export class MyEntitiesAPI extends BaseCRUDAPI<MyCreate, MyRead, MyUpdate> {
  baseRoute = routes.base
  itemRoute = routes.item

  // Extra method beyond CRUD:
  async getBySlug(slug: string) {
    return await this.requests.get<MyRead>(routes.bySlug(slug))
  }
}
```

Add the new class to `UserApiClient` in `client-user.ts`.

## `RequestResponse<T>` Pattern

**Every method returns `Promise<RequestResponse<T>>`**:
```typescript
interface RequestResponse<T> {
  response: AxiosResponse<T> | null
  data: T | null  // null on ANY failure
  error: any      // caught exception or null
}
```

```typescript
// Always destructure and check:
const { data, error } = await api.recipes.getOne(slug)
if (error) {
  console.error(error)
  return
}
if (data) {
  // data is Recipe (not null)
  console.log(data.name)
}
```

**TypeScript does not enforce null-checking on `data`**. Accessing `data.name` without a null check will throw at runtime when requests fail.

## `route()` URL Builder

```typescript
import { route } from '../base'  // or '../../base'

// Appends query params, filters null/undefined automatically
route('/api/recipes', { page: 1, perPage: 10, orderBy: 'name', filter: undefined })
// → '/api/recipes?page=1&perPage=10&orderBy=name'

// Array params become repeated keys:
route('/api/recipes', { ids: ['a', 'b'] })
// → '/api/recipes?ids=a&ids=b'
```

The function uses `new URL('http://localhost.com', rest)` internally and strips the prefix — always pass relative paths starting with `/api/`.

## Client Aggregators (Frozen Objects)

`UserApiClient`, `AdminAPI`, and `PublicApi` aggregate all domain sub-clients and are `Object.freeze()`'d at construction. You cannot add properties or mock individual APIs by assignment after construction. In tests, inject a mock `ApiRequestInstance` at construction time instead.

## Generated Types

`frontend/app/lib/api/types/` is **auto-generated from Python Pydantic models** via `pydantic-to-typescript2`. Files have a `/* DO NOT MODIFY BY HAND */` header.

To fix a wrong type: change the Python Pydantic model, then run `task dev:generate`.

For custom/augmented types that can't be generated, add to `frontend/app/types/` (hand-maintained) or `frontend/app/lib/api/types/non-generated.ts`.

**Type variant naming** (from generated files):
- `Create*` / `*In` → POST body
- `Save*` → internal with group_id/household_id added
- `Update*` → PUT body
- `*Out` → GET response
- `*Summary` → lightweight read-only view

Use `Out` for reads, `Create` for POST bodies, `Update` for PUT bodies. Never use `Save*` in frontend code.

## SSE Streaming (Recipe Creation)

`RecipeAPI.createOneByUrl()` uses Server-Sent Events via `sse.js` — it calls `useMealieAuth()` directly inside the class method. This only works from within a Vue setup context. Do not call SSE methods from Pinia actions or non-Vue contexts.

## Known Inconsistencies

- Class suffix is inconsistent: some classes use `API` (uppercase I), others use `Api` (lowercase i). New classes should use `Api`.
- `duplicateOne()` on `BaseCRUDAPI` is hardcoded to return `Recipe` type — don't call it on non-Recipe endpoints.
- `upload.ts` bypasses `ApiRequestInstance` and doesn't return `RequestResponse<T>` — wrap calls in `try/catch`.
