---
name: add-frontend-page
description: "
  Scaffold a new Nuxt 4 page with correct layout assignment, middleware, SEO meta, and API wiring.
  Use when adding a new route to the frontend.
  Do NOT use for admin pages (admin/ layout has different conventions) without also reading admin layout wiring.
---

## Before You Start

Read these files based on the page type:
- **Group page**: `frontend/app/pages/g/[groupSlug]/cookbooks/index.vue` — dual API fork (own/public)
- **Household page**: `frontend/app/pages/household/index.vue` — permission-gated, composable pattern
- **Admin page**: `frontend/app/pages/admin/manage/users/index.vue` — data table, delete dialog
- **Layout reference**: `frontend/app/layouts/default.vue`, `frontend/app/layouts/admin.vue`

## Page location and route structure

| Area | Directory | Middleware |
|------|-----------|------------|
| Group-scoped | `pages/g/[groupSlug]/` | `group-only` |
| Household-scoped | `pages/household/` | `can-manage-household-only` or `advanced-only` |
| Admin-only | `pages/admin/` | `admin-only` |
| Public explore | `pages/g/[groupSlug]/` | none (public) |
| Auth pages | `pages/` | none |

## Step 1: Create the page file

```vue
<!-- frontend/app/pages/{path}/{page-name}.vue -->
<script setup lang="ts">
// SEO meta — required on every page
useSeoMeta({
  title: computed(() => t('{domain}.page-title')),
});

// Access control — the ONLY mechanism for page-level guards
// The middleware is everything — there are no secondary checks inside page components
definePageMeta({
  layout: 'default',  // or 'admin', 'basic', 'blank'
  middleware: ['group-only'],  // or 'admin-only', 'advanced-only', 'can-manage-household-only'
});

const { t } = useI18n();
// Call useUserApi() ONCE at setup time
const api = useUserApi();

// For group pages — detect own vs. foreign group:
const route = useRoute();
const auth = useMealieAuth();
const isOwnGroup = computed(() => {
  return auth.user.value?.groupSlug === route.params.groupSlug;
});

// Data fetching with stable key (never hardcode string keys across pages)
const { data: items, pending } = await useAsyncData(
  useAsyncKey(),  // always use useAsyncKey() — never hardcode
  async () => {
    const { data, error } = await api.{entities}.getAll();
    if (error) {
      // handle error
      return [];
    }
    return data?.items ?? [];
  }
);
</script>

<template>
  <v-container>
    <BasePageTitle :title="t('{domain}.page-title')" />
    <v-card>
      <v-card-text>
        <!-- page content -->
      </v-card-text>
    </v-card>
  </v-container>
</template>
```

## Step 2: Layout-specific patterns

**Admin layout**: Admin pages must call `setPageLayout('admin')` in `onMounted` AND have `layout: 'admin'` in `definePageMeta`. Some admin pages have a quirk where the layout doesn't apply from `definePageMeta` alone:

```typescript
onMounted(() => {
  setPageLayout('admin');  // Required for some admin pages — check site-settings.vue
});
```

**Group pages with dual API fork**:

```typescript
// Different API for own group vs. exploring another group's content
const store = computed(() => {
  return isOwnGroup.value
    ? use{Entity}Store()  // authenticated store with CRUD
    : usePublic{Entity}Store(route.params.groupSlug as string);  // read-only
});
```

**Error handling for query params**:
```typescript
// Route.query values are always strings — parseISO on invalid string throws
import { parseISO, isValid } from 'date-fns';
const dateParam = route.query.date as string;
const date = dateParam && isValid(parseISO(dateParam)) ? parseISO(dateParam) : new Date();
```

## Step 3: Add navigation link (if page should appear in sidebar)

```typescript
// frontend/app/components/Layout/DefaultLayout.vue
// Add to the topLinks, cookbookLinks, or createLinks array:
const topLinks = computed<SideBarLink[]>(() => [
  // ... existing links ...
  {
    icon: $globals.icons.{icon},
    title: i18n.t('{domain}.nav-title'),
    to: `/g/${route.params.groupSlug}/{path}`,
    restricted: false,  // true = only shown to group owners
  },
]);
```

## Step 4: Add i18n keys

```json
// Only edit frontend/app/lang/en-US.json
// All other locale files are managed by Crowdin — do not edit them
{
  "{domain}": {
    "page-title": "My Page",
    "nav-title": "My Nav"
  }
}
```

## Verify

```bash
cd frontend
yarn lint --max-warnings=0 app/pages/{path}/{page-name}.vue
# Optionally start the dev server and navigate to the page:
yarn dev
```

## Common Mistakes

1. **Hardcoded `useAsyncData` key**: Using a hardcoded string key like `useAsyncData('recipes', ...)` on two pages causes silent data sharing. Always use `useAsyncKey()` to generate unique keys.
2. **Middleware is the only guard**: `definePageMeta({ middleware: ['admin-only'] })` is the ONLY access control for pages. There is no secondary check inside page components — if the middleware is bypassed, the page is unprotected.
3. **Query params accumulate**: Pages that add query params do not clean up automatically on unmount. Use `onBeforeRouteLeave` to clear params if needed.
4. **`create/index.vue` is a redirect stub**: `g/[groupSlug]/r/create/index.vue` has no template and immediately `router.push()`es on mount. If you copy this as a template, the content will flash and disappear.
