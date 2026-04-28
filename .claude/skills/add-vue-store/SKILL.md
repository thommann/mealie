---
name: add-vue-store
description: "
  Scaffold a new Vue 3 entity store composable following the module-level ref singleton
  and useStore factory pattern. Use when adding shared state for a new entity type.
  Do NOT use for component-local state (use ref directly in the component),
  or for the shopping list page (which has its own composable tree).
---

## Before You Start

Read these files:
- `frontend/app/composables/store/use-category-store.ts` — simplest complete store example
- `frontend/app/composables/store/use-cookbook-store.ts` — dual authenticated/public variant
- `frontend/app/composables/partials/use-store-factory.ts` — `useStore`, `useReadOnlyStore`
- `frontend/app/composables/partials/use-actions-factory.ts` — `useStoreActions` CRUD implementation
- `frontend/app/composables/store/index.ts` — `clearAllStores()` where you MUST register your reset

## Step 1: Create the store composable file

```typescript
// frontend/app/composables/store/use-{entity}-store.ts
import type { Ref } from 'vue';
import type { {Entity}Out } from '~/lib/api/types/{domain}';

// Module-level singletons — shared across ALL callers. This is intentional.
// These are NOT per-component refs.
const store: Ref<{Entity}Out[]> = ref([]);
const loading = ref(false);

export function use{Entity}Store() {
  const api = useUserApi();  // call inside the function, not at module scope
  return useStore('{entity}', store, loading, api.{entities});
  // Returns { store: Ref<{Entity}Out[]>, actions: { getAll, createOne, updateOne, deleteOne, refresh } }
}

// For public/unauthenticated variant (same store ref, separate loading state):
const publicLoading = ref(false);

export function usePublic{Entity}Store(groupSlug: string) {
  const api = usePublicExploreApi(groupSlug);
  return useReadOnlyStore('{entity}', store, publicLoading, api.explore.{entities});
}

// REQUIRED: reset function must zero both refs
export function reset{Entity}Store() {
  store.value = [];
  loading.value = false;
  publicLoading.value = false;
}
```

**The `store` ref is a module-level singleton.** `store.value` in one component IS the same object as in another component. This is by design — changes propagate reactively everywhere.

## Step 2: Register in store/index.ts

**This step is mandatory.** Missing it causes the previous user's data to leak into a new session after login.

```typescript
// frontend/app/composables/store/index.ts
// Add your export:
export { use{Entity}Store, reset{Entity}Store } from './use-{entity}-store';

// Add reset call inside clearAllStores():
export function clearAllStores() {
  // ... existing reset calls ...
  reset{Entity}Store();  // ADD THIS
}
```

## Step 3: Use in components

```typescript
// In <script setup lang="ts">
const { store: {entities}, actions } = use{Entity}Store();

// store is already a Ref<{Entity}Out[]> — use directly in template
// actions.getAll() fetches from API and updates store
// actions.createOne(data) POSTs and pushes to store

onMounted(async () => {
  await actions.getAll();  // auto-hydrates if store is empty
});
```

## Step 4: Auto-hydration behavior

`useStore()` auto-hydrates on first call if the store is empty. But note:
- If component A calls `use{Entity}Store()` and component B also calls it while A's fetch is in-flight, B gets the same ref and will see the result when A's fetch resolves
- If you need isolated per-component state (not shared), do NOT use the store factory — use `ref([])` directly inside the component

## Step 5: Data factory for forms (optional)

If you need a factory function for initializing create/edit forms:

```typescript
export function use{Entity}Data() {
  const data: Ref<Create{Entity}> = ref({
    name: '',
    // ... default values
  });

  function resetData() {
    data.value = { name: '' };
  }

  return { data, resetData };
}
```

## Verify

```bash
cd frontend
yarn lint --max-warnings=0 app/composables/store/use-{entity}-store.ts
yarn test:ci
```

## Common Mistakes

1. **Not adding `reset{Entity}Store()` to `clearAllStores()`**: The previous user's data is visible to the next logged-in user. This is a data privacy bug.
2. **Calling `useUserApi()` at module scope** (outside the function): The composable is evaluated at import time before Vue is mounted, capturing a stale auth instance.
3. **Sharing public and private store refs**: Both `use{Entity}Store()` and `usePublic{Entity}Store()` share the same `store` ref. The first one to call `getAll()` wins. Never use both variants on the same page.
4. **`useStoreActions` default orderBy**: The factory defaults to `orderBy: 'name'`. If your entity doesn't have a `name` field (or uses a different name), pass `params: { orderBy: 'created_at' }` as the fourth argument to `useStore()`.
