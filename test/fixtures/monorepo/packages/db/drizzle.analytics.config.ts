import { defineConfig } from "drizzle-kit";

export default defineConfig({
  dialect: "postgresql",
  schema: "./src/analytics/schema.ts",
  out: "./migrations/analytics",
});
