---
pluginSource: sdd-engineering-team
name: vision-mcp
description: Provides visual understanding capabilities through a Vision MCP server (or your image-understanding MCP). Use when analyzing screenshots, diagnosing error screenshots, understanding UI designs, interpreting diagrams, extracting text from images, comparing UI states, or any task that requires image/video understanding. Use when the human approver says "look at this image", "analyze this screenshot", "what does this error screenshot show", or "compare these two screenshots".
---

# Vision MCP Skill

## Overview

When the host model is not vision-enabled, this skill provides visual understanding through a configured Vision MCP server. Replace names like `zai-vision` or `GLM-4.6V` below with the actual provider configured in your deployment. When you need to "see" an image, screenshot, or video, use the MCP tools — never attempt to describe or analyze image content without them.

## Available MCP Tools

The Vision MCP server (`vision-mcp` — replace with your configured server name) provides these tools:

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `ui_to_artifact` | Turn UI screenshots into code, prompts, specs, or descriptions | A screenshot shows a UI design that needs to be built or documented |
| `extract_text_from_screenshot` | OCR for code, terminals, docs, and general text | A screenshot contains text, code snippets, terminal output, or document content |
| `diagnose_error_screenshot` | Analyze error snapshots and propose actionable fixes | A screenshot shows an error message, stack trace, crash dialog, or failed test output |
| `understand_technical_diagram` | Interpret architecture, flow, UML, ER, and system diagrams | A screenshot or image contains a technical diagram (architecture, flowchart, UML, ERD, etc.) |
| `analyze_data_visualization` | Read charts and dashboards to surface insights and trends | A screenshot contains charts, graphs, dashboards, or data visualizations |
| `ui_diff_check` | Compare two UI shots to flag visual or implementation drift | Two screenshots need to be compared for visual differences |
| `image_analysis` | General-purpose image understanding | None of the specific tools fit — fallback for any image analysis |
| `video_analysis` | Describe scenes, moments, and entities in video | A video file (local/remote, ≤8 MB, MP4/MOV/M4V) needs analysis |

## How to Use

### Critical Rules

1. **Always specify the image path or filename** in your tool call. The MCP server reads files from the local filesystem.
2. **Do NOT paste images into the conversation.** The client may transcode and try to send them directly to the non-vision model, which will fail. Instead, save the image to a local path and reference it.
3. **Use the browser_screenshot tool first**, then pass the resulting file path to the Vision MCP tool.

### Workflow: Analyzing Screenshots

```
Step 1: browser_screenshot → saves PNG to local path
Step 2: Pass that path to the appropriate Vision MCP tool
Step 3: Use the analysis result in your work
```

### Choosing the Right Tool

**Ask yourself what the image shows:**

- **UI / Design mockup?** → `ui_to_artifact`
- **Text, code, or terminal output?** → `extract_text_from_screenshot`
- **Error message, crash, or failure?** → `diagnose_error_screenshot`
- **Architecture or flow diagram?** → `understand_technical_diagram`
- **Chart, graph, or dashboard?** → `analyze_data_visualization`
- **Two screenshots to compare?** → `ui_diff_check`
- **Something else entirely?** → `image_analysis`

## Usage by Role

### Debugger

When investigating visual bugs or UI issues:
1. Take a screenshot of the problematic state using `browser_screenshot`
2. Use `diagnose_error_screenshot` if it shows an error
3. Use `ui_diff_check` to compare broken vs expected states
4. Include the MCP analysis in your diagnosis report

### Full Stack Engineer

When implementing UI features or fixing visual bugs:
1. Take a screenshot of the current state
2. Use `ui_to_artifact` to generate code/specs from design screenshots
3. Use `ui_diff_check` to verify implementation matches design
4. Use `extract_text_from_screenshot` to read any text-based reference material

### Quality Engineer

When validating UI or testing visual regressions:
1. Take screenshots of the current implementation
2. Use `ui_diff_check` to compare against reference screenshots
3. Use `diagnose_error_screenshot` if visual errors appear
4. Document visual findings with MCP-generated analysis

### Product Manager

When reviewing designs or specifications:
1. Use `ui_to_artifact` to convert UI mockups into specs
2. Use `understand_technical_diagram` to interpret architecture diagrams
3. Use `analyze_data_visualization` to extract insights from dashboard screenshots

## Best Practices

1. **Save images to the workspace** before analyzing. Use a consistent location (e.g., `tmp/` or the working directory).
2. **Be specific in your request.** Instead of "analyze this image", tell the tool what you're looking for: "Extract the error message and suggest a fix" or "Identify the UI components and generate React code for this layout."
3. **Combine with browser tools.** Navigate to the page, take a screenshot, then analyze — don't ask someone to manually provide images.
4. **For video analysis**, ensure the file is ≤8 MB and in MP4/MOV/M4V format.
5. **Quota awareness.** Vision MCP servers may enforce quota or rate limits — use the tools intentionally, not casually.

## Integration with Browser Tools

The browser tools (`browser_screenshot`, `browser_snapshot`) work together with Vision MCP:

| Scenario | Tool Sequence |
|----------|---------------|
| See what a page looks like | `browser_screenshot` → `image_analysis` |
| Read error in browser | `browser_screenshot` → `diagnose_error_screenshot` |
| Check UI matches design | `browser_screenshot` (actual) + reference image → `ui_diff_check` |
| Extract text from webpage | `browser_screenshot` → `extract_text_from_screenshot` |
| Understand a dashboard | `browser_screenshot` → `analyze_data_visualization` |

Note: For accessibility tree analysis (identifying elements to interact with), use `browser_snapshot` directly — no Vision MCP needed.
