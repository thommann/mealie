# frontend/ — Nuxt 4 / Vue 3 SPA

Client-side SPA (`ssr: false`) for the Mealie recipe manager. Source lives under `frontend/app/` (Nuxt 4 convention). All backend communication goes through `/api/**` which the Nuxt server proxies to the FastAPI backend.

## Quick Commands

```bash
cd frontend
yarn install         # install dependencies
yarn dev             # dev server
yarn build           # production build
yarn generate        # static site generation (used in CI)
yarn lint --max-warnings=0  # must pass before PR
yarn test:ci         # unit tests
```

## Project Structure

```
frontend/
├── nuxt.config.ts          # SSR disabled, runtime config, path aliases
├── app/                    # Nuxt 4 source root (auto-imported)
│   ├── pages/              # File-based routes
│   ├── components/
│   │   ├── Domain/         # Feature-specific stateful components
│   │   ├── global/         # Reusable primitives (Base*, App*, The*)
│   │   └── Layout/         # App shell (header, sidebar, snackbar)
│   ├── composables/        # Vue 3 composables (state management)
│   │   ├── store/          # Per-entity CRUD stores
│   │   └── partials/       # Generic store/action factory functions
│   ├── lib/api/            # Typed API client classes
│   │   ├── base/           # BaseCRUDAPI, route() URL builder
│   │   ├── user/           # UserApiClient + domain sub-APIs
│   │   ├── admin/          # AdminAPI
│   │   ├── public/         # PublicApi, explore APIs
│   │   └── types/          # AUTO-GENERATED — never edit
│   ├── layouts/            # Nuxt layout templates
│   ├── middleware/         # Route guards
│   ├── plugins/            # axios.ts, init-auth.client.ts, theme.ts, globals.ts
│   ├── lang/               # i18n locale files (only edit en-US.json)
│   └── types/              # Hand-written TS types (not generated)
└── server/                 # Nuxt server routes — proxy to FastAPI
```

## Key Concepts

### API Client Pattern

```typescript
// Always instantiate via composables, never directly
const api = useUserApi()  // returns frozen UserApiClient
const { data, error } = await api.recipes.getOne(slug)
if (error) { /* handle error */ }
if (data) { /* data is Recipe */ }
```

**`data` is always `T | null`** — check for null before use. TypeScript will not warn you.

Call `useUserApi()` once at component setup time, not inside event handlers or loops (creates a new class instance each call).

### State Management (No Pinia/Vuex)

```typescript
// Module-level singleton ref — shared across all callers
const store: Ref<Category[]> = ref([])
const loading = ref(false)

export function useCategoryStore() {
  return useStore(storeKey, store, loading, api)  // auto-hydrates on first use
}

export function resetCategoryStore() {
  store.value = []
  loading.value = false
}
```

**Call `clearAllStores()` on logout** — module-level refs survive navigation and will show the previous user's data if not cleared.

### Component Organization

| Category | Prefix/Location | Rule |
|----------|-----------------|------|
| Domain components | `Domain/<Feature>/` | Stateful; call composables and API |
| Global primitives | `global/`, prefix `Base*` | No business logic; pure UI |
| App-level singletons | `global/`, prefix `App*` or `The*` | Mounted once per layout |
| Layout shell | `Layout/` | Wires header, sidebar, snackbar |

**Global components must not import composables or API utilities.** If a global component needs API data, lift state into the calling Domain component and pass via props.

### i18n

```typescript
// In <script setup>
const { t } = useI18n()
const message = t('some.key')

// In template
<span>{{ $t('some.key') }}</span>
```

**Only `en-US.json` may be modified by contributors.** All other locales (`de-DE.json`, `fr-FR.json`, etc.) are managed by Crowdin and must never be edited directly.

### Icons

Always use the icon registry — never hardcode MDI icon strings:
```typescript
const { $globals } = useNuxtApp()
// In template:
<v-icon>{{ $globals.icons.edit }}</v-icon>
```

### TypeScript Types

`frontend/app/lib/api/types/` files are **auto-generated**. After any Pydantic schema change on the backend:
```bash
task dev:generate
```
This runs `pydantic-to-typescript2` and regenerates all type files. Manual edits will be overwritten.

For types that can't be generated, add to `frontend/app/types/` (hand-maintained).

## Vue Conventions

- All components use `<script setup lang="ts">` — no Options API.
- Two-way binding: use `defineModel<T>()` (Vue 3.4+) — not the old `modelValue` prop + `emit('update:modelValue')` pattern.
- Use `withDefaults(defineProps<Interface>(), {...})` for components needing typed defaults.
- Export interfaces from `.vue` files when they're co-located with the component they serve: `import type { TableHeaders } from '~/components/global/CrudTable.vue'`.

## Nuxt Specifics

- `pathPrefix: false` in `nuxt.config.ts` — components are registered without directory namespace. Use `<RecipeCard>` not `<DomainRecipeRecipeCard>`.
- `~` alias = `frontend/app/` — use for all internal imports.
- `definePageMeta({ middleware: ['admin-only'] })` is the ONLY access control mechanism for pages — there are no secondary checks inside page components.
- `useAsyncData(useAsyncKey(), async () => {...})` for server-side-compatible data fetching. Always use `useAsyncKey()` — never hardcode string keys.
- Layout selection: `definePageMeta({ layout: 'admin' | 'basic' | 'blank' })`. Default layout is used when unspecified.
