---
name: add-vue-component
description: "
  Scaffold a new Vue 3 component following Mealie conventions: script setup, typed props,
  typed emits, i18n, icon registry, Vuetify leaf layer.
  Use when adding a new UI component in Domain/ or global/.
  Do NOT use for pages (use add-frontend-page) or for modifying auto-generated type files.
---

## Before You Start

Read these files based on the type of component:
- **Domain component**: `frontend/app/components/Domain/Recipe/RecipeCard.vue` — canonical feature component
- **Global primitive**: `frontend/app/components/global/BaseButton.vue` — semantic boolean props pattern
- **Dialog component**: `frontend/app/components/global/BaseDialog.vue` — v-model + loading + keep-open
- **Form-heavy component**: `frontend/app/components/global/AutoForm.vue` — complex slot/props pattern

## Component placement rules

| Type | Directory | Rule |
|------|-----------|------|
| Domain (stateful, API-connected) | `components/Domain/{Feature}/` | May import composables and API |
| Global primitive | `components/global/` | NO composables, NO API imports |
| App-level singleton | `components/global/`, prefix `App*` | Mounted once per layout |
| Layout shell | `components/Layout/` | Wires header, sidebar, snackbar |

**`pathPrefix: false` in `nuxt.config.ts`** means components are registered globally without directory prefixes. A file at `Domain/Recipe/Card.vue` registers as `<Card>`, not `<DomainRecipeCard>`. Name collisions are possible — use specific names.

## Step 1: Create the component file

```vue
<!-- frontend/app/components/Domain/{Feature}/{ComponentName}.vue -->
<script setup lang="ts">
// Always script setup, always TypeScript — no Options API
const { t } = useI18n();
const { $globals } = useNuxtApp();

// Typed props with defaults
const props = withDefaults(
  defineProps<{
    modelValue: {EntityOut} | null;
    readonly?: boolean;
    title?: string;
  }>(),
  {
    readonly: false,
    title: '',
  }
);

// For two-way binding (Vue 3.4+) — use defineModel instead of modelValue prop:
// const model = defineModel<{EntityOut} | null>();

// Typed emits using call-signature form:
const emit = defineEmits<{
  (e: 'update:modelValue', value: {EntityOut}): void;
  (e: 'delete', id: string): void;
  (e: 'save'): void;
}>();

// API client — call ONCE at setup time, never inside event handlers
const api = useUserApi();

// Toast notifications
const { alert } = useToast();  // from ~/composables/use-toast

async function handleSave() {
  const { data, error } = await api.{entities}.updateOne(props.modelValue!.id, formData.value);
  if (error) {
    alert.error(t('{domain}.save-error'));
    return;
  }
  if (data) {
    emit('update:modelValue', data);
    emit('save');
    alert.success(t('{domain}.save-success'));
  }
}
</script>

<template>
  <v-card>
    <v-card-title>{{ title || t('{domain}.default-title') }}</v-card-title>
    <v-card-text>
      <!-- Always use icon registry — never hardcode MDI strings -->
      <v-icon>{{ $globals.icons.edit }}</v-icon>
      <!-- Never use v-html without DOMPurify — it's an ESLint error -->
      <!-- <div v-html="unsafeContent" />  WRONG -->
      <!-- Use SafeMarkdown component instead: -->
      <SafeMarkdown :source="description" />
    </v-card-text>
    <v-card-actions>
      <BaseButton save @click="handleSave" />
      <BaseButton cancel @click="emit('save')" />
    </v-card-actions>
  </v-card>
</template>
```

## Step 2: i18n keys

```json5
// Only edit frontend/app/lang/en-US.json — other locales are managed by Crowdin
{
  "{domain}": {
    "default-title": "My Entity",
    "save-success": "Saved successfully",
    "save-error": "Failed to save"
  }
}
```

## Step 3: For global components — no business logic

```vue
<!-- components/global/BaseMyWidget.vue -->
<script setup lang="ts">
// Global components must NOT import composables or API utilities
// This boundary is convention-only — Nuxt won't enforce it

const props = withDefaults(
  defineProps<{
    label?: string;
    disabled?: boolean;
    variant?: 'flat' | 'outlined' | 'text';
  }>(),
  {
    label: '',
    disabled: false,
    variant: 'flat',
  }
);

// Map semantic props to Vuetify attrs
const color = computed(() => {
  if (props.disabled) return 'grey';
  return 'primary';
});
</script>
```

## Verify

```bash
cd frontend
yarn lint --max-warnings=0 app/components/Domain/{Feature}/{ComponentName}.vue
yarn test:ci
```

## Common Mistakes

1. **`v-html` without DOMPurify**: `vue/no-v-html: error` is enabled in ESLint. Use `<SafeMarkdown :source="content" />` for markdown content.
2. **Direct recipe prop mutation in Parts/ components**: `RecipePage` uses direct mutation of the recipe prop throughout the component tree (acknowledged as a convention violation). For new components, prefer emitting events and letting the parent update.
3. **Announcement file naming**: Files in `components/Domain/Announcement/Announcements/` MUST be named `YYYY-MM-DD_N_slug.vue`. The `announcements.test.ts` file validates this with `import.meta.glob` and WILL fail CI.
4. **Hardcoded MDI strings**: Always use `$globals.icons.{iconName}` from the icon registry. Hardcoded `mdi-edit` strings are not tree-shakeable and harder to change globally.
