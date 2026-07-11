export const meta = {
  name: "stats-page-feature",
  description: "Inspect Pindrop navigation, analytics data, UI conventions, and tests for a Stats page implementation.",
  argsSchema: {
    type: "object",
    properties: {
      request: { type: "string" },
    },
    required: ["request"],
    additionalProperties: false,
  },
  whenToUse: "When implementing or reviewing the Pindrop Stats page and its Home-page entry point.",
  phases: [
    { title: "inspect", detail: "Inspect navigation, analytics, and UI/test concerns in parallel" },
    { title: "synthesize", detail: "Produce a focused implementation and verification plan" },
  ],
}

export async function run(args, api) {
  const fastModel = api.model("fast")
  const synthesisModel = api.model("synthesis", fastModel)

  await api.phase("inspect")
  const prompts = [
    `Inspect this SwiftUI repository's main navigation and Home dashboard for the requested Stats page. Focus on Pindrop/UI/Main/MainWindow.swift and DashboardView.swift. Identify exact integration points, callback changes, shortcut ordering, and likely regressions. Do not edit files. Return concise findings with file paths. Request: ${args.request}`,
    `Inspect analytics-related code and models in this SwiftUI repository for a rich Stats page. Focus on DashboardStatsService, TranscriptionRecord fields, and pure presentation helpers/tests. Propose useful computable stats and chart datasets without inventing unavailable data. Do not edit files. Return concise findings with file paths. Request: ${args.request}`,
    `Inspect the current Pindrop visual system and tests for adding an interactive, animated Stats page consistent with Home. Focus on reusable components, accessibility/reduced-motion expectations, localization obligations, and exact tests to add or update. Do not edit files. Return concise findings with file paths. Request: ${args.request}`,
  ]
  const findings = await api.parallel(
    prompts.map((prompt, index) => () => api.agent(prompt, {
      label: `stats-inspection-${index}`,
      model: fastModel,
    })),
  )

  await api.phase("synthesize")
  const final = await api.agent(
    `Synthesize a minimal but polished implementation plan for the requested Stats page. Resolve conflicts, prioritize a buildable first version, and include exact files, datasets, interactions, accessibility, localization, and tests. Do not edit files.\n\nRequest: ${args.request}\n\nFindings:\n${findings.join("\n\n---\n\n")}`,
    { label: "stats-feature-synthesis", model: synthesisModel },
  )

  return { findings, final }
}
