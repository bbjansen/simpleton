import { defineConfig } from "vitest/config";

// The appcast generation (`buildAppcast`) is a pure function with no runtime
// bindings, so the standard Node-based Vitest environment is sufficient. This
// deliberately avoids pulling in @cloudflare/vitest-pool-workers to keep the
// dependency surface minimal (org policy: minimize dependencies).
export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node",
  },
});
