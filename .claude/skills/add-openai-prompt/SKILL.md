---
name: add-openai-prompt
description: "
  Scaffold a new OpenAI prompt: create the .txt file in the correct subdirectory, add the corresponding
  Pydantic response schema inheriting OpenAIBase, wire the get_response() call in the appropriate service,
  and add a unit test. Use when adding new AI-powered extraction or generation features.
  Do NOT use for modifying existing prompts (edit the .txt file directly).
---

## Before You Start

Read these files:
- `mealie/services/openai/openai.py` — `OpenAIService.get_response()` and prompt loading
- `mealie/schema/openai/_base.py` — `OpenAIBase`, `parse_openai_response()`
- `mealie/schema/openai/recipe_ingredient.py` — example extraction schema with field descriptions
- `mealie/services/openai/prompts/recipes/parse-recipe-ingredients.txt` — example prompt
- `tests/unit_tests/services_tests/test_openai_service.py` — test patterns

**OpenAI schemas are different from regular Pydantic schemas**: Field `description=` strings are prompt instructions to the model — write them as imperative commands, not developer documentation.

## Step 1: Create the prompt .txt file

```
# Choose subdirectory:
# - mealie/services/openai/prompts/recipes/  — recipe extraction/analysis
# - mealie/services/openai/prompts/general/  — general tasks (transcription, classification)

# mealie/services/openai/prompts/recipes/{feature-name}.txt
```

Prompt writing guidelines:
- Use the schema.org Recipe format as the canonical output format
- Include a hallucination guard: "Do not invent information not present in the source."
- Write extraction instructions as imperatives: "Convert fractions to decimals."
- Specify the output format explicitly

Example:
```text
You are a recipe assistant. Extract the recipe from the provided text.

Guidelines:
- Do not invent or add information not explicitly present in the source text.
- Convert all fractions to decimal numbers (e.g. 1/2 → 0.5).
- If a field is not present, omit it (do not use null or empty string).
- Return times in ISO 8601 duration format (e.g. PT30M for 30 minutes).
```

## Step 2: Create the Pydantic response schema

```python
# mealie/schema/openai/{feature_name}.py
from pydantic import Field, field_validator
from mealie.schema.openai._base import OpenAIBase


class OpenAI{Feature}Item(OpenAIBase):
    # Field descriptions are prompt instructions — write imperatively
    name: str = Field(description="The canonical ingredient name. Normalize to singular form.")
    quantity: float = Field(
        description="The numeric quantity as a decimal. Convert fractions. Return 0 if not present."
    )
    unit: str | None = Field(None, description="The unit of measurement. Normalize to common abbreviations.")
    notes: str | None = Field(None, description="Preparation notes (e.g., 'finely diced'). Omit if none.")

    @field_validator("quantity", mode="before")
    @classmethod
    def convert_none_to_zero(cls, v):
        """Coerce None to 0 — the model sometimes returns null for missing quantities."""
        return v if v is not None else 0


class OpenAI{Feature}Response(OpenAIBase):
    # OpenAI requires a top-level object — lists cannot be the root response type
    items: list[OpenAI{Feature}Item] = Field(
        description="The extracted items. Return an empty list if none found."
    )
```

**Field `description=` strings are sent to OpenAI as part of the JSON schema** — write them as model instructions, not code documentation.

## Step 3: Register in __init__.py

```bash
# Run the generator to update mealie/schema/openai/__init__.py:
python dev/code-generation/gen_schema_exports.py
# Or manually add:
# from mealie.schema.openai.{feature_name} import OpenAI{Feature}Response  # noqa: F401
```

## Step 4: Wire into the service

```python
# In the relevant service file:
from mealie.schema.openai.{feature_name} import OpenAI{Feature}Response
from mealie.services.openai.openai import OpenAIService

async def {feature_name}_with_ai(self, data: str) -> list[...]:
    # ALWAYS guard against OPENAI_ENABLED being False
    if not self.settings.OPENAI_ENABLED:
        raise ValueError("OpenAI is not configured")

    service = OpenAIService()
    # Prompt path uses dot-notation: "recipes.{feature-name}" maps to prompts/recipes/{feature-name}.txt
    result = await service.get_response(
        prompt_name="recipes.{feature-name}",
        message=data,
        response_schema=OpenAI{Feature}Response,
        # For batch processing:
        # func=process_batch, workers=self.settings.OPENAI_WORKERS
    )
    # parse_openai_response() returns None on failure — always check
    if result is None:
        return []
    return result.items
```

## Step 5: Write a unit test

```python
# tests/unit_tests/services_tests/test_{feature_name}_openai.py
from unittest.mock import AsyncMock, patch
import pytest
from mealie.schema.openai.{feature_name} import OpenAI{Feature}Response, OpenAI{Feature}Item


def test_prompt_loads_successfully():
    """Verify the prompt file exists and loads without error."""
    from mealie.services.openai.openai import OpenAIService
    # This tests that the .txt file exists and the path mapping works
    service = OpenAIService.__new__(OpenAIService)
    prompt = service._get_prompt("recipes.{feature-name}")
    assert len(prompt) > 0
    assert "Do not invent" in prompt  # hallucination guard


def test_response_schema_validates():
    items = [{"name": "flour", "quantity": 1.5, "unit": "cup"}]
    response = OpenAI{Feature}Response(items=[OpenAI{Feature}Item(**i) for i in items])
    assert len(response.items) == 1
    assert response.items[0].quantity == 1.5
```

## Common Mistakes

1. **`OpenAIService()` without checking `OPENAI_ENABLED`**: The constructor raises `ValueError` immediately if OpenAI is not configured. Always guard with `if self.settings.OPENAI_ENABLED`.
2. **List as root response type**: OpenAI's structured output requires a top-level object. Wrap lists in a container class (`class Response(OpenAIBase): items: list[Item]`).
3. **`parse_openai_response()` returns None silently**: Never skip the None check after `get_response()`. Silent None processing produces empty results with no error.
4. **Descriptive field descriptions instead of imperative**: "The quantity of the ingredient" (bad) vs "Convert fractions to decimals. Return 0 if not present." (good). OpenAI uses descriptions as instructions.
