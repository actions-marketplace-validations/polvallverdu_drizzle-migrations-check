import { defineConfig } from "drizzle-kit";

export default defineConfig({
  dialect: "postgresql",
  schema: "./src/users/schema.ts",
  out: "./migrations/users",
});
