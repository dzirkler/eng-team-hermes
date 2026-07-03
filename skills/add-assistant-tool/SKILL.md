---
pluginSource: sdd-engineering-team
name: add-assistant-tool
description: 'Add a new tool to the AI assistant. Use when: adding a new tool to the chat assistant, registering a new function the AI can call, extending assistant capabilities with a new tool, creating a new server-side tool for the chat API.'
---

# Add Assistant Tool

## When to Use
- Adding a new tool the AI assistant can invoke
- Registering a new server-side function in the chat API
- Extending the assistant's capabilities with a new action

## Architecture Overview

The assistant tool system has **three parts** that must be kept in sync:

1. **Server-side tool** (`<chat-api-route>.ts` — e.g., `app/api/chat/route.ts`) — the tool definition with `description`, `inputSchema`, and `execute` function
2. **UI rendering** (`<assistant-thread-component>.tsx`) — icon, display label, and visual rendering in the Chain of Thought
3. **System prompt guidance** (`<system-prompt-file>.md`) — instructions telling the AI when and how to use the tool

All three must be updated when adding a new tool. Missing any part causes silent failures.

## Step-by-Step Procedure

### Step 1: Define the Server-Side Tool

**File**: `<chat-api-route>.ts` (e.g., `app/api/chat/route.ts`)

Add the new tool to the `tools: { ... }` object in the `streamText()` call. Follow this pattern:

```typescript
your_tool_name: tool({
  description: "Clear, concise description of what the tool does and when to use it",
  inputSchema: zodSchema(
    z.object({
      param1: z.string().describe("Description of param1"),
      param2: z.boolean().optional().describe("Description of param2"),
    })
  ),
  execute: async ({ param1, param2 }) => {
    // Call backend API or perform logic
    // Return a serializable result object
    return { result: "data" };
  },
}),
```

**Key rules**:
- Tool names use `snake_case` (e.g., `search_content`, `list_campaigns`)
- The `description` is what the LLM reads to decide whether to call the tool — be specific about when to use it
- Use `.optional()` for parameters that aren't required
- Use `.describe()` on every parameter — the LLM uses these descriptions
- Return plain objects (no class instances, no functions)
- If the tool can fail, include an `error` field in the return value
- The backend API is at `BACKEND_URL` (already defined in the file)

### Step 2: Choose an Icon and Label

**File**: `<assistant-thread-component>.tsx`

Find the two mapping objects near the `ToolAdapter` function:

#### 2a. Add to `TOOL_ICONS`

Choose from these icon categories, or use `WrenchIcon` as the fallback:

| Category | Icons | Example Tools |
|----------|-------|---------------|
| Discovery/search | `SearchIcon` | search, list, browse, query |
| File/content | `FileTextIcon` | read, view content |
| Navigation | `MousePointerClickIcon` | open, select, navigate |
| Fallback | `WrenchIcon` | any generic tool |

```typescript
const TOOL_ICONS: Record<string, typeof WrenchIcon> = {
  // ...existing entries...
  your_tool_name: SearchIcon,  // or FileTextIcon, MousePointerClickIcon, WrenchIcon
};
```

**Import the icon** from `lucide-react` if not already imported at the top of the file:

```typescript
import { /* ...existing... */, YourNewIcon } from "lucide-react";
```

#### 2b. Add to `TOOL_LABELS`

Provide a short, user-friendly display name:

```typescript
const TOOL_LABELS: Record<string, string> = {
  // ...existing entries...
  your_tool_name: "Friendly Name",  // shown in the Chain of Thought UI
};
```

**Label guidelines**:
- Use Title Case (e.g., "Search", "List Campaigns", "Read Content")
- Keep it short (2-3 words max)
- Use an action verb that describes what the tool does

### Step 3: Update the System Prompt

**File**: `<system-prompt-file>.md`

Add guidance under the `## Tool Usage Rules` section about when and how the AI should use the new tool. Keep it concise — one or two bullet points.

Example additions:
- If the tool is for a new action: `- When a user asks to [do X], use the \`your_tool_name\` tool with [parameters].`
- If the tool extends existing behavior: `- For [specific scenario], prefer \`your_tool_name\` over other methods.`

### Step 4: Handle Navigation Side-Effects (if applicable)

If the new tool causes navigation in the UI (like `select_content` does):

**File**: `<navigation-hook>.ts` (e.g., `hooks/use-select-content-navigation.ts`)

Either extend the existing hook or create a new one following the same pattern:
- Scan `parts` for your tool's name
- Use a `useRef<Set<string>>` for deduplication
- Call the appropriate context functions (`setSelectedFile`, `toggleCampaign`, etc.)
- Mount the hook in `AssistantMessage` in `thread.tsx`

### Step 5: Rebuild and Verify

1. Rebuild the Docker stack:
   ```
   docker compose up -d --build <frontend-service>
   ```

2. Verify in the browser:
   - Open `http://localhost:<dev-port>`
   - Open the assistant panel
   - Trigger the tool by asking a question that requires it
   - Expand the Chain of Thought to confirm the tool appears with the correct icon and label
   - Verify the tool's result is correct
   - Verify any navigation side-effects work

3. Check for build errors — missing imports or type mismatches will surface at build time

## Checklist

- [ ] Server-side tool added to `<chat-api-route>.ts` in the `tools` object
- [ ] Tool icon added to `TOOL_ICONS` in `<assistant-thread-component>.tsx`
- [ ] Tool icon imported from `lucide-react` (if new)
- [ ] Tool label added to `TOOL_LABELS` in `<assistant-thread-component>.tsx`
- [ ] System prompt updated in `<system-prompt-file>.md`
- [ ] Navigation side-effect hook updated (if tool affects UI navigation)
- [ ] Docker rebuild succeeds with no errors
- [ ] Verified tool works in the browser
