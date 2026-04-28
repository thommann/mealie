# frontend/app/composables/ — Vue 3 Composables

The state management and business logic layer for the frontend. Replaces Pinia/Vuex with a composable-first architecture using module-level reactive refs.

## Core Pattern: Module-Level Shared Refs

```typescript
// State is declared at module scope — shared across ALL callers
const store: Ref<Category[]> = ref([])
const loading = ref(false)

export function useCategoryStore(i18n?: Composer) {
  const api = useUserApi(i18n)
  return useStore('category', store, loading, api.categories)
  // auto-hydrates on first call if store is empty
}

export function resetCategoryStore() {
  store.value = []
  loading.value = false
}
```

**This is not per-component state.** `store.value` in one component is the same object as in another. Changes propagate everywhere reactively.

## Store Factory Pattern (`partials/`)

`partials/use-store-factory.ts` exports:
- `useStore(key, store, loading, api)` — full CRUD, auto-hydrates
- `useReadOnlyStore(key, store, loading, api)` — read-only, auto-hydrates

Both return `{ store, actions }` where:
- `store` — the shared `Ref<T[]>`
- `actions` — `{ getAll, createOne, updateOne, deleteOne, refresh }` (from `use-actions-factory.ts`)

`partials/use-actions-factory.ts` exports `useStoreActions()` and `useReadOnlyActions()` — these implement the actual CRUD calls and state mutations.

## Adding a New Store

1. Create `store/use-<entity>-store.ts`
2. Declare module-level `const store: Ref<T[]> = ref([])` and `const loading = ref(false)`
3. Export `useXStore()` using the factory
4. Export `resetXStore()` zeroing both refs
5. **Add to `store/index.ts`**: re-export and add `resetXStore()` call in `clearAllStores()`

Missing step 5 = stale data after logout.

## Dual Authenticated/Public Store Pattern

Most entity stores expose both variants (same `store` ref, separate loading states):

```typescript
const loading = ref(false)      // for useCategoryStore
const publicLoading = ref(false) // for usePublicCategoryStore

export function useCategoryStore() {
  const api = useUserApi()
  return useStore('category', store, loading, api.categories)
}

export function usePublicCategoryStore(groupSlug: string) {
  const api = usePublicExploreApi(groupSlug)
  return useReadOnlyStore('category', store, publicLoading, api.explore.categories)
}
```

Both share the same `store` ref. Whichever runs first wins until `resetXStore()` is called. Only use one variant per page context.

## Shopping List Composables

The shopping list page uses a two-level composable tree:

```
use-shopping-list-page.ts  ← orchestrator, owns lifecycle hooks
├── use-shopping-list-state.ts   ← Ref<ShoppingList> + listItems split
├── use-shopping-list-data.ts    ← polling (5s), offline guards, loadingCounter
├── use-shopping-list-crud.ts    ← optimistic updates, offline queue
├── use-shopping-list-sorting.ts ← groupAndSortListItemsByFood, preserveItemOrder
├── use-shopping-list-labels.ts  ← labelOpenState initialization
├── use-shopping-list-recipes.ts ← recipe reference management
└── use-shopping-list-copy.ts    ← clipboard operations
```

**`itemsByLabel` is NOT a computed property** — it's a plain reactive object updated manually by `updateListItemOrder()`. After any item mutation, you must call `updateListItemOrder()` or the display won't update.

**`loadingCounter`** — a `Ref<number>` incremented before async operations and decremented after. Polling is skipped when `> 0`. Always decrement in a `finally` block.

## API Composables (`api/`)

```typescript
// Always call once per component at setup time
const api = useUserApi()         // authenticated user endpoints
const api = useAdminApi()        // admin endpoints
const api = usePublicApi()       // unauthenticated endpoints
const api = usePublicExploreApi(groupSlug)  // public group explore
```

Each call creates a new class instance — calling inside event handlers creates many redundant objects. Cache the result in a `const`.

`useDownloader` is NOT in the barrel export — import directly:
```typescript
import { useDownloader } from '~/composables/api/use-downloader'
```

## Common Gotchas

**Module-level ref pollution**: `allRecipes` and `recentRecipes` in `composables/recipes/use-recipes.ts` are module-level singletons. Two components mounting simultaneously can clobber each other's data. Use `useLazyRecipes()` for instance-level isolated state.

**Reactive sub-composable params**: Sub-composables accept `Ref<T>` parameters. Passing a plain (non-ref) value silently breaks reactivity — watchers won't update. Always pass `ref(value)` or `toRef(obj, 'key')`.

**`useGlobalI18n()` timing**: Only call from within a composable function body, never at module scope outside a function — it caches the first i18n instance it receives and will capture null if called too early.
