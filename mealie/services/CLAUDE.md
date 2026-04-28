# mealie/services/ — Business Logic Layer

Service classes encapsulate all business logic. They receive `AllRepositories` via constructor injection, perform operations using repos, and raise domain exceptions. They have no HTTP awareness.

## BaseService

All services must inherit `BaseService` and call `super().__init__()` **last**:

```python
from mealie.services._base_service import BaseService

class MyService(BaseService):
    def __init__(self, repos: AllRepositories, user: PrivateUser):
        self.repos = repos
        self.user = user
        super().__init__()  # MUST be last — sets self.dirs, self.settings, self.logger
```

`BaseService` provides:
- `self.logger` — module-level logger
- `self.settings` — `AppSettings` singleton
- `self.dirs` — `AppDirs` with data/backup/recipe directories

## Service Domains

| Directory | What it owns |
|-----------|--------------|
| `recipe/` | RecipeService (CRUD, permissions, duplication), RecipeDataService (filesystem), RecipeBulkActionsService, TemplateService |
| `scraper/` | Strategy-cascade web scraper; cleaner pipeline; bulk importer |
| `openai/` | AsyncOpenAI wrapper; prompt loading with custom-override support |
| `parser_services/` | ABCIngredientParser + brute/NLP/OpenAI implementations; DataMatcher fuzzy matching |
| `migrations/` | BaseMigrator template + 11 concrete format importers |
| `event_bus_service/` | EventBusService; Apprise and webhook listeners/publishers |
| `scheduler/` | SchedulerRegistry; asyncio loop service; scheduled tasks |
| `group_services/` | GroupService (creation, storage), MultiPurposeLabelService |
| `household_services/` | HouseholdService, ShoppingListService (complex merge algorithm) |
| `user_services/` | UserService (lock/unlock, admin operations) |
| `backups_v2/` | BackupV2 orchestrator; AlchemyExporter; BackupFile ZIP handler |
| `email/` | EmailService with ABCEmailSender injection for testability |

## Recipe Service Pattern

`RecipeServiceBase` validates tenant context (group/household ID consistency) in `__init__`. Services that carry authenticated context inherit this pattern:

```python
class RecipeServiceBase(BaseService):
    def __init__(self, repos, user, household, translator):
        self.repos = repos
        self.user = user
        # self.group_recipes → group-scoped (reads, all households)
        # self.repos.recipes → household-scoped (writes)
        super().__init__()
```

**Use `self.group_recipes` for lookups** (sees all group recipes regardless of household). **Use `self.repos.recipes` for mutations** (household-scoped). Mixing these causes silent data-scope bugs.

## Scraper Strategy Chain

`DEFAULT_SCRAPER_STRATEGIES` in `scraper/scraper.py` is tried in order — first non-None result wins:
1. `RecipeScraperPackage` — recipe-scrapers library (schema.org)
2. `RecipeScraperOpenAITranscription` — yt-dlp + OpenAI (video URLs)
3. `RecipeScraperOpenAI` — GPT on raw HTML
4. `RecipeScraperOpenGraph` — extruct og: tags fallback

To add a strategy: implement `ABCScraperStrategy` and insert into the list at the correct priority.

## OpenAI Integration

```python
service = OpenAIService()  # raises ValueError if OPENAI_ENABLED is False
# Always guard:
if self.settings.OPENAI_ENABLED:
    service = OpenAIService()
    result = await service.get_response(
        prompt_name="recipes.parse-recipe-ingredients",
        message=ingredient_text,
        response_schema=OpenAIIngredients,
    )
```

Prompts are `.txt` files in `services/openai/prompts/`. Operators can shadow them via `OPENAI_CUSTOM_PROMPT_DIR`. Field `description=` in OpenAI schemas are model prompt instructions — write them as imperative commands.

## Event Bus

```python
# From a controller (with BackgroundTasks)
self.publish_event(
    EventTypes.recipe_created,
    document_data=EventRecipeData(operation=EventOperation.create, recipe_id=recipe.id),
    group_id=self.group_id,
    household_id=self.household_id,
)

# From a scheduler task (synchronous, no BackgroundTasks)
bus = EventBusService()  # no bg=
await bus.dispatch(INTERNAL_INTEGRATION_ID, group_id, household_id, event_type, data)
```

Adding a new `EventTypes` value requires: (1) enum member, (2) DB migration adding column to `GroupEventNotifierOptions`, (3) matching field in `GroupEventNotifierOptions` schema.

## Ingredient Parser

Three strategies via `get_parser(RegisteredParser, group_id, session, translator)`:
- `RegisteredParser.brute` — rule-based, no DB, binary confidence
- `RegisteredParser.nlp` — external `ingredient_parser` library
- `RegisteredParser.openai` — GPT structured output, chunked async

`DataMatcher` lazily loads all group foods/units into memory on first call. Fuzzy matching via `rapidfuzz`: 85% threshold for foods, 70% for units. Unit+food recombination fallback: if individual matches fail, tries `f"{unit} {food}"` as a food.

## Migration Framework

```python
class MyFormatMigrator(BaseMigrator):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.name = "myformat"
        self.key_aliases = [
            MigrationAlias(key="recipeYield", alias="servings"),
            MigrationAlias(key="cookTime", alias="perform_time", func=format_time),
        ]

    def _migrate(self) -> None:
        # Extract archive, read format, call self.rewrite_alias()
        # then self.import_recipes_to_database(recipes)
        # Never let exceptions escape — append to self.report_entries instead
        ...
```

Register in `routes/groups/controller_migrations.py` dispatch table.
